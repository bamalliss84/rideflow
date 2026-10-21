"""WebSocket authentication: `?token=<access JWT>` (browsers cannot set headers on WebSocket upgrades).

Resolves user, tenant (claim `tid`) and active membership exactly like REST; the scope is closed (4401)
when anything is missing. Tokens in URLs must never be logged by proxies in production (documented risk).
"""

from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken


@database_sync_to_async
def _resolve(raw_token):
    from apps.accounts.models import User
    from apps.core.context import system_context
    from apps.tenancy.models import MembershipStatus, Tenant, TenantMembership

    try:
        token = AccessToken(raw_token)
    except TokenError:
        return None
    if token.get("scope") != "tenant":
        return None
    with system_context():
        user = User.objects.filter(pk=token.get("uid"), is_active=True).first()
        tenant = Tenant.objects.filter(pk=token.get("tid")).first()
        if user is None or tenant is None:
            return None
        roles = set(
            TenantMembership.all_tenants.filter(tenant=tenant, user=user, status=MembershipStatus.ACTIVE).values_list(
                "role", flat=True
            )
        )
    if not roles:
        return None
    return {"user_id": str(user.pk), "tenant_id": str(tenant.pk), "roles": sorted(roles)}


class JWTWebSocketAuthMiddleware:
    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get("query_string", b"").decode())
        token = (query.get("token") or [""])[0]
        scope["rideflow"] = await _resolve(token) if token else None
        return await self.inner(scope, receive, send)
