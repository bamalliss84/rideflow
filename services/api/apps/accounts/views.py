from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, Throttled, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core import audit
from apps.core.context import tenant_context
from apps.core.permissions import STAFF_ROLES, permissions_for_roles
from apps.core.throttling import IPScopedThrottle, PhoneThrottle, ScopedTenantThrottle
from apps.tenancy.models import AppType, MembershipStatus, Role, TenantMembership

from . import mfa, otp
from .authentication import APP_HEADER, issue_tokens, resolve_app
from .models import MFADevice, PhoneOTP, User
from .serializers import (
    AppContextSerializer,
    LoginResponseSerializer,
    LogoutSerializer,
    MeSerializer,
    MFAChallengeSerializer,
    MFASessionSerializer,
    MFASetupResponseSerializer,
    MFATokenSerializer,
    MFAVerifySerializer,
    OTPRequestResponseSerializer,
    OTPRequestSerializer,
    OTPVerifySerializer,
    PlatformLoginSerializer,
    UserSerializer,
)

APP_PARAM = OpenApiParameter(
    APP_HEADER,
    str,
    OpenApiParameter.HEADER,
    required=True,
    description="Client id of the registered tenant application (trusted app context).",
)


class OTPRequestView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [PhoneThrottle, IPScopedThrottle]
    throttle_scope = "otp_request"

    @extend_schema(request=OTPRequestSerializer, responses={202: OTPRequestResponseSerializer}, parameters=[APP_PARAM], tags=["auth"])
    def post(self, request):
        app = resolve_app(request)
        serializer = OTPRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        with tenant_context(app.tenant):
            code = otp.generate_code()
            try:
                otp.send_code(phone, code, app.tenant)
            except otp.OTPProviderUnavailable:
                return Response({"code": "otp_unavailable", "detail": "OTP delivery is unavailable."}, status=503)
            PhoneOTP.objects.create(
                phone=phone,
                app=app,
                code_hash=otp.hash_code(phone, code),
                expires_at=timezone.now() + timedelta(seconds=settings.OTP_TTL_SECONDS),
            )
        return Response({"status": "sent", "expires_in": settings.OTP_TTL_SECONDS}, status=status.HTTP_202_ACCEPTED)


ROLE_FOR_APP = {AppType.RIDER: Role.RIDER, AppType.DRIVER: Role.DRIVER}


def _challenge(user, *, scope, tenant=None, app=None):
    device = MFADevice.objects.filter(user=user).first()
    return {
        "mfa_required": True,
        "mfa_token": mfa.make_challenge(user, scope=scope, tenant=tenant, app=app),
        "mfa_enrolled": bool(device and device.is_confirmed),
        "expires_in": mfa.CHALLENGE_TTL,
    }


class AppContextView(APIView):
    """Public, minimal description of an application context (login screens show the operator name)."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(responses=AppContextSerializer, parameters=[APP_PARAM], tags=["auth"])
    def get(self, request):
        app = resolve_app(request)
        return Response(
            {
                "tenant_name": app.tenant.name,
                "app_type": app.app_type,
                "locale": app.tenant.locale,
                "tenant_status": app.tenant.status,
            }
        )


def _challenge_user(token):
    try:
        data = mfa.read_challenge(token)
    except mfa.ChallengeInvalid:
        return None, None
    user = User.objects.filter(pk=data.get("uid"), is_active=True).first()
    return user, data


def _challenge_invalid():
    return Response({"code": "mfa_challenge_invalid", "detail": "Sign in again."}, status=401)


class MFASetupView(APIView):
    """Starts (or restarts, while unconfirmed) TOTP enrolment for the user of a valid MFA challenge."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [IPScopedThrottle]
    throttle_scope = "mfa"

    @extend_schema(request=MFATokenSerializer, responses={200: MFASetupResponseSerializer}, tags=["auth"])
    def post(self, request):
        serializer = MFATokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user, _data = _challenge_user(serializer.validated_data["mfa_token"])
        if user is None:
            return _challenge_invalid()
        device = MFADevice.objects.filter(user=user).first()
        if device is not None and device.is_confirmed:
            return Response({"code": "mfa_already_enrolled", "detail": "An authenticator is already enrolled."}, status=409)
        secret = mfa.new_secret()
        MFADevice.objects.update_or_create(
            user=user, defaults={"secret_encrypted": mfa.encrypt_secret(secret), "confirmed_at": None, "last_used_step": 0}
        )
        account = user.phone
        return Response(
            {"secret": secret, "otpauth_uri": mfa.provisioning_uri(secret, account), "account": account, "issuer": mfa.ISSUER}
        )


class MFAVerifyView(APIView):
    """Second factor. Confirms enrolment on first use and issues MFA-verified tokens."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [IPScopedThrottle]
    throttle_scope = "mfa"

    @extend_schema(request=MFAVerifySerializer, responses={200: MFASessionSerializer}, tags=["auth"])
    def post(self, request):
        from apps.tenancy.models import Tenant, TenantApplication

        serializer = MFAVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data["mfa_token"]
        user, data = _challenge_user(token)
        if user is None:
            return _challenge_invalid()
        if not mfa.register_attempt(token):
            return Response({"code": "mfa_attempts_exceeded", "detail": "Too many attempts; sign in again."}, status=429)
        with transaction.atomic():
            device = MFADevice.objects.select_for_update().filter(user=user).first()
            if device is None:
                return Response({"code": "mfa_not_enrolled", "detail": "Set up an authenticator first."}, status=409)
            step = mfa.matching_step(mfa.decrypt_secret(device.secret_encrypted), serializer.validated_data["code"])
            if step is None or step <= device.last_used_step:
                return Response({"code": "mfa_invalid", "detail": "Invalid or already used code."}, status=400)
            enrolling = not device.is_confirmed
            device.last_used_step = step
            if enrolling:
                device.confirmed_at = timezone.now()
            device.save()
            if data["scope"] == "platform":
                if not user.is_platform_admin:
                    return _challenge_invalid()
                audit.record(
                    "platform.login", request=request, actor=user, target=user, tenant_id=None, data={"mfa_enrolled_now": enrolling}
                )
                return Response(
                    {**issue_tokens(user, scope="platform", mfa=True), "scope": "platform", "user_id": user.pk, "tenant": None}
                )
            tenant = Tenant.objects.filter(pk=data.get("tid")).first()
            app = TenantApplication.objects.filter(client_id=data.get("app"), is_active=True).first()
            if tenant is None or app is None or app.tenant_id != tenant.pk:
                return _challenge_invalid()
            with tenant_context(tenant):
                roles = sorted(
                    TenantMembership.objects.filter(user=user, status=MembershipStatus.ACTIVE).values_list("role", flat=True)
                )
                if not set(roles) & STAFF_ROLES:
                    raise PermissionDenied("No administrative membership for this operator.")
                audit.record(
                    "auth.login",
                    request=request,
                    actor=user,
                    target=user,
                    data={"app": app.client_id, "app_type": app.app_type, "mfa": True, "mfa_enrolled_now": enrolling},
                )
        tokens = issue_tokens(user, scope="tenant", tenant=tenant, app=app, mfa=True)
        return Response(
            {
                **tokens,
                "scope": "tenant",
                "user_id": user.pk,
                "tenant": {"tenant_id": tenant.pk, "tenant_name": tenant.name, "roles": roles},
            }
        )


class OTPVerifyView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [PhoneThrottle, IPScopedThrottle]
    throttle_scope = "otp_verify"

    @extend_schema(
        request=OTPVerifySerializer,
        responses={200: LoginResponseSerializer},
        parameters=[APP_PARAM],
        tags=["auth"],
        description="Rider/driver apps receive tokens. The admin app receives an MFA challenge (MFAChallenge) instead.",
    )
    def post(self, request):
        app = resolve_app(request)
        serializer = OTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        code = serializer.validated_data["code"]
        tenant = app.tenant
        with tenant_context(tenant), transaction.atomic():
            challenge = (
                PhoneOTP.objects.select_for_update()
                .filter(phone=phone, app=app, consumed_at__isnull=True, expires_at__gt=timezone.now())
                .order_by("-created_at")
                .first()
            )
            if challenge is None:
                return Response({"code": "otp_expired", "detail": "No valid code for this phone; request a new one."}, status=400)
            if challenge.attempts >= settings.OTP_MAX_ATTEMPTS:
                raise Throttled(detail="Too many attempts; request a new code.")
            if challenge.code_hash != otp.hash_code(phone, code):
                challenge.attempts += 1
                challenge.save(update_fields=["attempts", "updated_at"])
                # Returning (not raising) commits the attempt counter.
                return Response({"code": "otp_invalid", "detail": "Incorrect code."}, status=400)
            challenge.consumed_at = timezone.now()
            challenge.save(update_fields=["consumed_at", "updated_at"])

            user = User.objects.filter(phone=phone).first()
            is_new = user is None
            if is_new:
                user = User.objects.create_user(phone, full_name=serializer.validated_data.get("full_name", ""))
            if not user.is_active:
                raise PermissionDenied("Account disabled.")

            if app.app_type in ROLE_FOR_APP:
                role = ROLE_FOR_APP[app.app_type]
                membership, _ = TenantMembership.objects.get_or_create(user=user, role=role, tenant=tenant)
                if membership.status != MembershipStatus.ACTIVE:
                    raise PermissionDenied("Membership suspended for this operator.")
                if role == Role.DRIVER:
                    from apps.drivers.services import ensure_driver_profile

                    ensure_driver_profile(user)
            else:
                staff = TenantMembership.objects.filter(user=user, role__in=STAFF_ROLES, status=MembershipStatus.ACTIVE)
                if not staff.exists():
                    raise PermissionDenied("No administrative membership for this operator.")
                if settings.ADMIN_MFA_REQUIRED:
                    roles = sorted(staff.values_list("role", flat=True))
                    audit.record("auth.first_factor_ok", request=request, actor=user, target=user, data={"app": app.client_id})
                    return Response(
                        {
                            **_challenge(user, scope="tenant", tenant=tenant, app=app),
                            "tenant": {"tenant_id": tenant.pk, "tenant_name": tenant.name, "roles": roles},
                        }
                    )

            roles = sorted(TenantMembership.objects.filter(user=user, status=MembershipStatus.ACTIVE).values_list("role", flat=True))
            audit.record(
                "auth.login",
                request=request,
                actor=user,
                target=user,
                data={"app": app.client_id, "app_type": app.app_type, "new_user": is_new},
            )
        tokens = issue_tokens(user, scope="tenant", tenant=tenant, app=app)
        return Response(
            {
                **tokens,
                "user_id": user.pk,
                "is_new_user": is_new,
                "tenant": {"tenant_id": tenant.pk, "tenant_name": tenant.name, "roles": roles},
            }
        )


class PlatformLoginView(APIView):
    """Password login for RideFlow platform staff only. MFA is a documented Phase 2 blocker."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedTenantThrottle]
    throttle_scope = "platform_login"

    @extend_schema(request=PlatformLoginSerializer, responses={200: MFAChallengeSerializer}, tags=["auth"])
    def post(self, request):
        serializer = PlatformLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = User.objects.filter(phone=serializer.validated_data["phone"], is_active=True).first()
        if user is None or not user.is_platform_admin or not user.check_password(serializer.validated_data["password"]):
            return Response({"code": "invalid_credentials", "detail": "Invalid credentials."}, status=401)
        if settings.ADMIN_MFA_REQUIRED:
            audit.record("platform.first_factor_ok", request=request, actor=user, target=user, tenant_id=None)
            return Response(_challenge(user, scope="platform"))
        audit.record("platform.login", request=request, actor=user, target=user, tenant_id=None)
        return Response(issue_tokens(user, scope="platform"))


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(request=LogoutSerializer, responses={205: None}, tags=["auth"])
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            token = RefreshToken(serializer.validated_data["refresh"])
        except TokenError:
            raise ValidationError({"refresh": "Invalid token."})
        if str(token.get("uid")) != str(request.user.pk):
            raise ValidationError({"refresh": "Token does not belong to this user."})
        token.blacklist()
        return Response(status=status.HTTP_205_RESET_CONTENT)


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def _payload(self, request):
        tenant = getattr(request, "tenant", None)
        roles = sorted(getattr(request, "tenant_roles", []) or [])
        driver_profile_id = None
        if tenant is not None and "driver" in roles:
            from apps.drivers.models import DriverProfile

            driver_profile_id = DriverProfile.objects.filter(user=request.user).values_list("id", flat=True).first()
        device = MFADevice.objects.filter(user=request.user).first()
        scope = getattr(request, "auth_scope", "tenant")
        return {
            "user": UserSerializer(request.user).data,
            "scope": scope,
            "is_platform_admin": bool(request.user.is_platform_admin and scope == "platform"),
            "mfa": {
                "enrolled": bool(device and device.is_confirmed),
                "session_verified": bool(request.auth and request.auth.get("mfa")),
            },
            "currency_minor_units": tenant.currency_minor_units if tenant else None,
            "tenant": {"tenant_id": tenant.pk, "tenant_name": tenant.name, "roles": roles} if tenant else None,
            "permissions": sorted(permissions_for_roles(roles)),
            "driver_profile_id": driver_profile_id,
            "currency": tenant.currency if tenant else None,
            "time_zone": tenant.time_zone if tenant else None,
        }

    @extend_schema(responses=MeSerializer, tags=["auth"])
    def get(self, request):
        return Response(self._payload(request))

    @extend_schema(request=UserSerializer, responses=MeSerializer, tags=["auth"])
    def patch(self, request):
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(self._payload(request))
