from .context import get_current_tenant_id
from .logging import get_request_id
from .models import AuditEvent


def _client_ip(request):
    if request is None:
        return None
    return request.META.get("REMOTE_ADDR")


def record(action, *, request=None, actor=None, target=None, data=None, tenant_id=None):
    """Write an immutable audit event. Tenant defaults to the active tenant context."""
    if actor is None and request is not None and getattr(request, "user", None) and request.user.is_authenticated:
        actor = request.user
    roles = sorted(getattr(request, "tenant_roles", []) or []) if request is not None else []
    return AuditEvent.objects.create(
        tenant_id=tenant_id if tenant_id is not None else get_current_tenant_id(),
        actor=actor,
        actor_roles=roles,
        action=action,
        target_type=type(target).__name__ if target is not None else "",
        target_id=str(getattr(target, "pk", "")) if target is not None else "",
        data=data or {},
        request_id=get_request_id(),
        ip_address=_client_ip(request),
    )
