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

from . import otp
from .authentication import APP_HEADER, issue_tokens, resolve_app
from .models import PhoneOTP, User
from .serializers import (
    LoginResponseSerializer,
    LogoutSerializer,
    MeSerializer,
    OTPRequestResponseSerializer,
    OTPRequestSerializer,
    OTPVerifySerializer,
    PlatformLoginSerializer,
    TokenPairSerializer,
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


class OTPVerifyView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [PhoneThrottle, IPScopedThrottle]
    throttle_scope = "otp_verify"

    @extend_schema(request=OTPVerifySerializer, responses={200: LoginResponseSerializer}, parameters=[APP_PARAM], tags=["auth"])
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

    @extend_schema(request=PlatformLoginSerializer, responses={200: TokenPairSerializer}, tags=["auth"])
    def post(self, request):
        serializer = PlatformLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = User.objects.filter(phone=serializer.validated_data["phone"], is_active=True).first()
        if user is None or not user.is_platform_admin or not user.check_password(serializer.validated_data["password"]):
            return Response({"code": "invalid_credentials", "detail": "Invalid credentials."}, status=401)
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
        return {
            "user": UserSerializer(request.user).data,
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
