"""Tenant role/permission model.

A user has zero or more active TenantMembership roles inside the tenant bound to their token.
Permissions are derived from roles in code (versioned with the API) and checked on every endpoint.
"""

from rest_framework.permissions import BasePermission

ALL_STAFF_PERMISSIONS = frozenset(
    {
        "members.manage",
        "config.manage",
        "geo.manage",
        "drivers.view",
        "drivers.review",
        "subscriptions.view",
        "subscriptions.review",
        "subscriptions.manage",
        "rides.view",
        "disputes.review",
        "violations.review",
        "enforcement.manage",
        "reports.view",
        "audit.view",
    }
)

ROLE_PERMISSIONS = {
    "owner": ALL_STAFF_PERMISSIONS,
    "admin": ALL_STAFF_PERMISSIONS,
    "reviewer": frozenset({"drivers.view", "drivers.review", "rides.view", "disputes.review", "violations.review", "reports.view"}),
    "finance": frozenset({"subscriptions.view", "subscriptions.review", "subscriptions.manage", "drivers.view", "reports.view"}),
    "support": frozenset({"rides.view", "drivers.view", "subscriptions.view"}),
    "rider": frozenset(),
    "driver": frozenset(),
}

STAFF_ROLES = frozenset({"owner", "admin", "reviewer", "finance", "support"})


def permissions_for_roles(roles):
    perms = set()
    for role in roles:
        perms |= ROLE_PERMISSIONS.get(role, frozenset())
    return perms


def request_roles(request):
    return getattr(request, "tenant_roles", frozenset())


def has_tenant_permission(request, perm):
    return perm in permissions_for_roles(request_roles(request))


class IsTenantMember(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and getattr(request, "tenant", None))


class HasRole(IsTenantMember):
    role = None

    def has_permission(self, request, view):
        return super().has_permission(request, view) and self.role in request_roles(request)


class IsRider(HasRole):
    role = "rider"


class IsDriver(HasRole):
    role = "driver"


class IsRiderOrDriver(IsTenantMember):
    def has_permission(self, request, view):
        return super().has_permission(request, view) and bool({"rider", "driver"} & set(request_roles(request)))


class TenantPermission(IsTenantMember):
    """Checks `view.required_permission` (str) or `view.required_permissions[<action or method>]`."""

    message = "You do not have permission for this tenant operation."

    def has_permission(self, request, view):
        if not super().has_permission(request, view):
            return False
        perm = getattr(view, "required_permission", None)
        mapping = getattr(view, "required_permissions", None)
        if mapping:
            action = getattr(view, "action", None)
            perm = mapping.get(action) or mapping.get(request.method) or mapping.get("*", perm)
        if not perm:
            return False
        return has_tenant_permission(request, perm)


class IsPlatformAdmin(BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.is_platform_admin
            and getattr(request, "auth_scope", None) == "platform"
        )
