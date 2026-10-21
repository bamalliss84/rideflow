import secrets
import uuid

from django.conf import settings
from django.core.validators import RegexValidator
from django.db import models

from apps.core.models import AppendOnlyMixin, TenantScopedModel


class TenantStatus(models.TextChoices):
    ACTIVE = "active", "Active"
    SUSPENDED = "suspended", "Suspended"


class Tenant(models.Model):
    """An independent transportation operator (platform-level record, D017)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=160)
    slug = models.SlugField(max_length=64, unique=True)
    status = models.CharField(max_length=16, choices=TenantStatus.choices, default=TenantStatus.ACTIVE)
    currency = models.CharField(max_length=3, validators=[RegexValidator(r"^[A-Z]{3}$")])
    currency_minor_units = models.PositiveSmallIntegerField(default=2)
    time_zone = models.CharField(max_length=64, default="UTC")
    locale = models.CharField(max_length=16, default="ar")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name

    @property
    def is_active(self):
        return self.status == TenantStatus.ACTIVE


class AppType(models.TextChoices):
    RIDER = "rider", "Rider app"
    DRIVER = "driver", "Driver app"
    ADMIN = "admin", "Tenant administration web"


def _client_id():
    return f"app_{secrets.token_urlsafe(12)}"


class TenantApplication(models.Model):
    """A registered client application (e.g. a white-label rider app) bound to exactly one tenant.

    Unauthenticated calls (OTP) identify the tenant only through `X-RideFlow-App: <client_id>`, which the
    app ships with; tenant ids are never accepted from request bodies. Platform-level record.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tenant = models.ForeignKey(Tenant, on_delete=models.PROTECT, related_name="applications")
    name = models.CharField(max_length=120)
    app_type = models.CharField(max_length=16, choices=AppType.choices)
    client_id = models.CharField(max_length=64, unique=True, default=_client_id)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.tenant.slug}:{self.app_type}:{self.client_id}"


class Role(models.TextChoices):
    RIDER = "rider", "Rider"
    DRIVER = "driver", "Driver"
    OWNER = "owner", "Tenant owner"
    ADMIN = "admin", "Tenant administrator"
    REVIEWER = "reviewer", "Reviewer (drivers, disputes, violations)"
    FINANCE = "finance", "Finance (deposits, plans)"
    SUPPORT = "support", "Support (read-only operations)"


class MembershipStatus(models.TextChoices):
    ACTIVE = "active", "Active"
    SUSPENDED = "suspended", "Suspended"


class TenantMembership(TenantScopedModel):
    """Global user identity + per-tenant membership/role (owner decision: global identity, tenant memberships)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="memberships")
    role = models.CharField(max_length=16, choices=Role.choices)
    status = models.CharField(max_length=16, choices=MembershipStatus.choices, default=MembershipStatus.ACTIVE)
    display_name = models.CharField(max_length=120, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["tenant", "user", "role"], name="uniq_membership_role")]
        indexes = [models.Index(fields=["tenant", "role", "status"])]


class TenantConfig(AppendOnlyMixin, TenantScopedModel):
    """Versioned tenant policy (ADR-0003). `params` holds overrides; effective policy = defaults + overrides.

    Rows are never edited: a change creates a new version. Rides store the version they were created under.
    """

    version = models.PositiveIntegerField()
    effective_from = models.DateTimeField()
    params = models.JSONField(default=dict)
    note = models.CharField(max_length=240, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")

    class Meta:
        ordering = ["-version"]
        constraints = [models.UniqueConstraint(fields=["tenant", "version"], name="uniq_tenant_config_version")]
