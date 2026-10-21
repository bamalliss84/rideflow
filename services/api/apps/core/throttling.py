"""Throttles whose cache keys are namespaced by tenant (ADR-0001 §6)."""

from rest_framework.throttling import AnonRateThrottle, SimpleRateThrottle, UserRateThrottle

from .context import get_current_tenant_id


def _tenant_prefix():
    return str(get_current_tenant_id() or "none")


class TenantUserRateThrottle(UserRateThrottle):
    def get_cache_key(self, request, view):
        key = super().get_cache_key(request, view)
        return f"t:{_tenant_prefix()}:{key}" if key else None


class TenantAnonRateThrottle(AnonRateThrottle):
    def get_cache_key(self, request, view):
        key = super().get_cache_key(request, view)
        return f"t:{_tenant_prefix()}:{key}" if key else None


class ScopedTenantThrottle(SimpleRateThrottle):
    """Per-scope throttle keyed by user (or IP) and tenant. Views set `throttle_scope`."""

    def __init__(self):
        pass

    def allow_request(self, request, view):
        self.scope = getattr(view, "throttle_scope", None)
        if not self.scope:
            return True
        self.rate = self.get_rate()
        self.num_requests, self.duration = self.parse_rate(self.rate)
        return super().allow_request(request, view)

    def get_cache_key(self, request, view):
        ident = request.user.pk if request.user and request.user.is_authenticated else self.get_ident(request)
        return f"throttle_{self.scope}_t:{_tenant_prefix()}_{ident}"


class IPScopedThrottle(ScopedTenantThrottle):
    """Per-client-IP limit using the `<scope>_ip` rate. Kept higher than per-phone limits because many mobile
    users share carrier NAT addresses."""

    def allow_request(self, request, view):
        base = getattr(view, "throttle_scope", None)
        if not base:
            return True
        self.scope = f"{base}_ip"
        self.rate = self.get_rate()
        self.num_requests, self.duration = self.parse_rate(self.rate)
        return SimpleRateThrottle.allow_request(self, request, view)

    def get_cache_key(self, request, view):
        return f"throttle_{self.scope}_{self.get_ident(request)}"


class PhoneThrottle(ScopedTenantThrottle):
    """Throttles OTP endpoints per phone number (in addition to per-IP) to limit SMS abuse (T10)."""

    def get_cache_key(self, request, view):
        phone = str(request.data.get("phone", ""))[:32] if hasattr(request, "data") else ""
        app = request.headers.get("X-RideFlow-App", "")
        return f"throttle_{self.scope}_app:{app}_phone:{phone}"
