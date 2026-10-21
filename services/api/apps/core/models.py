import uuid

from django.conf import settings
from django.db import models

from .context import CrossTenantWrite, TenantContextMissing, get_current_tenant, get_current_tenant_id, require_tenant


class TenantQuerySet(models.QuerySet):
    """A queryset built without tenant context is empty AND raises as soon as it would touch the database.

    Building it must not raise (libraries such as django-filter introspect `_default_manager.all().query`
    at import time), but executing it always does: fail closed and loud.
    """

    _tenant_missing = False

    def _clone(self):
        clone = super()._clone()
        clone._tenant_missing = self._tenant_missing
        return clone

    def _guard(self):
        if self._tenant_missing:
            raise TenantContextMissing("Tenant-scoped query executed without an active tenant context.")

    def _fetch_all(self):
        self._guard()
        super()._fetch_all()

    def iterator(self, *args, **kwargs):
        self._guard()
        return super().iterator(*args, **kwargs)

    def count(self):
        self._guard()
        return super().count()

    def exists(self):
        self._guard()
        return super().exists()

    def aggregate(self, *args, **kwargs):
        self._guard()
        return super().aggregate(*args, **kwargs)

    def update(self, **kwargs):
        self._guard()
        return super().update(**kwargs)

    def delete(self):
        self._guard()
        return super().delete()

    def get(self, *args, **kwargs):
        self._guard()
        return super().get(*args, **kwargs)


class TenantManager(models.Manager.from_queryset(TenantQuerySet)):
    """Default manager for tenant-scoped models: always filtered by the active tenant, fails closed without one."""

    def get_queryset(self):
        tenant = get_current_tenant()
        queryset = super().get_queryset()
        if tenant is None:
            queryset = queryset.none()
            queryset._tenant_missing = True
            return queryset
        return queryset.filter(tenant_id=tenant.pk)

    def create(self, **kwargs):
        require_tenant()
        return super().create(**kwargs)


class TenantScopedModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tenant = models.ForeignKey("tenancy.Tenant", on_delete=models.PROTECT, related_name="+", editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = TenantManager()
    # Explicit, greppable escape hatch for trusted cross-tenant code (platform jobs, admin, seed).
    all_tenants = models.Manager()

    class Meta:
        abstract = True

    def save(self, *args, **kwargs):
        current = get_current_tenant_id()
        if self.tenant_id is None:
            if current is None:
                require_tenant()
            self.tenant_id = current
        elif current is not None and self.tenant_id != current:
            raise CrossTenantWrite(f"{type(self).__name__} belongs to another tenant")
        super().save(*args, **kwargs)


class AppendOnlyMixin:
    """Marks a model whose rows may never be updated or deleted (enforced by a DB trigger too)."""

    APPEND_ONLY = True

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise RuntimeError(f"{type(self).__name__} is append-only")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise RuntimeError(f"{type(self).__name__} is append-only")


class AuditEvent(AppendOnlyMixin, models.Model):
    """Immutable audit trail. tenant is null for platform-level events (tenant provisioning, platform logins)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tenant = models.ForeignKey("tenancy.Tenant", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    actor_roles = models.JSONField(default=list, blank=True)
    action = models.CharField(max_length=80)
    target_type = models.CharField(max_length=80, blank=True)
    target_id = models.CharField(max_length=64, blank=True)
    data = models.JSONField(default=dict, blank=True)
    request_id = models.CharField(max_length=64, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["tenant", "created_at"]),
            models.Index(fields=["tenant", "action"]),
            models.Index(fields=["target_type", "target_id"]),
        ]

    def __str__(self):
        return f"{self.action} {self.target_type}:{self.target_id}"


class IdempotencyRecord(models.Model):
    """Stored outcome of a mutation keyed by (user, Idempotency-Key) so retries after reconnect replay safely."""

    id = models.BigAutoField(primary_key=True)
    tenant = models.ForeignKey("tenancy.Tenant", null=True, blank=True, on_delete=models.CASCADE, related_name="+")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    key = models.CharField(max_length=128)
    scope = models.CharField(max_length=200)
    request_hash = models.CharField(max_length=64)
    response_status = models.PositiveSmallIntegerField(null=True)
    response_body = models.JSONField(null=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "key"], name="uniq_idempotency_user_key")]

    def __str__(self):
        return f"{self.scope} [{self.key}]"
