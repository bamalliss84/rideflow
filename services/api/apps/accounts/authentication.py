from django.conf import settings
from rest_framework import status
from rest_framework.exceptions import APIException, AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core import context
from apps.tenancy.models import Tenant, TenantApplication

APP_HEADER = "X-RideFlow-App"


class AppContextInvalid(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = "A valid application context is required."
    default_code = "app_invalid"


def issue_tokens(user, *, scope, tenant=None, app=None, mfa=False):
    refresh = RefreshToken.for_user(user)
    refresh["scope"] = scope
    if mfa:
        refresh["mfa"] = True
    if tenant is not None:
        refresh["tid"] = str(tenant.pk)
    if app is not None:
        refresh["app"] = app.client_id
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def resolve_app(request, *, required=True):
    """Resolves the trusted application context from the X-RideFlow-App header."""
    client_id = request.headers.get(APP_HEADER, "").strip()
    if not client_id:
        if required:
            raise AppContextInvalid(f"{APP_HEADER} header is required.", code="app_required")
        return None
    app = TenantApplication.objects.select_related("tenant").filter(client_id=client_id, is_active=True).first()
    if app is None:
        raise AppContextInvalid("Unknown or inactive application.", code="app_invalid")
    return app


def bind_request(request, *, tenant=None, roles=frozenset(), scope="tenant"):
    for target in (request, getattr(request, "_request", None)):
        if target is None:
            continue
        target.tenant = tenant
        target.tenant_roles = roles
        target.auth_scope = scope


class TenantJWTAuthentication(JWTAuthentication):
    """JWT auth that binds the tenant from the token claim `tid` (never from the client payload).

    Membership is re-checked on every request so suspension/revocation is immediate.
    """

    def authenticate(self, request):
        result = super().authenticate(request)
        if result is None:
            return None
        user, token = result
        scope = token.get("scope")
        mfa_ok = bool(token.get("mfa")) or not settings.ADMIN_MFA_REQUIRED
        if scope == "platform":
            if not user.is_platform_admin:
                raise AuthenticationFailed("Platform access revoked.", code="platform_revoked")
            if not mfa_ok:
                raise AuthenticationFailed("Multi-factor authentication is required.", code="mfa_required")
            bind_request(request, scope="platform")
            return user, token
        if scope != "tenant":
            raise AuthenticationFailed("Invalid token scope.", code="token_scope")
        tenant = Tenant.objects.filter(pk=token.get("tid")).first()
        if tenant is None:
            raise AuthenticationFailed("Unknown tenant.", code="tenant_invalid")
        header_app = request.headers.get(APP_HEADER, "").strip()
        if header_app:
            app = TenantApplication.objects.filter(client_id=header_app, is_active=True).first()
            if app is None or app.tenant_id != tenant.pk:
                raise AuthenticationFailed("Application does not belong to the token tenant.", code="tenant_mismatch")
        context.activate_tenant(tenant)
        from apps.tenancy.services import active_roles

        roles = active_roles(user)
        if not mfa_ok:
            # Staff roles are only granted to MFA-verified sessions (a rider-app token never carries them).
            from apps.core.permissions import STAFF_ROLES

            roles = roles - STAFF_ROLES
        if not roles:
            context.set_locked()
            raise AuthenticationFailed("No active membership in this tenant.", code="membership_inactive")
        bind_request(request, tenant=tenant, roles=roles, scope="tenant")
        return user, token
