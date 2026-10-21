from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.core import audit
from apps.core.context import require_tenant
from apps.core.exceptions import Conflict

from . import policy
from .models import MembershipStatus, TenantConfig, TenantMembership


def create_config_version(*, overrides, user=None, note="", effective_from=None, request=None, replace=False):
    """Creates the next config version. By default merges with the previous overrides (partial update)."""
    require_tenant()
    clean = policy.validate_overrides(overrides)
    with transaction.atomic():
        previous = TenantConfig.objects.order_by("-version").first()
        params = {} if replace or previous is None else dict(previous.params)
        params.update(clean)
        try:
            with transaction.atomic():
                config = TenantConfig.objects.create(
                    version=(previous.version + 1) if previous else 1,
                    effective_from=effective_from or timezone.now(),
                    params=params,
                    note=note,
                    created_by=user,
                )
        except IntegrityError:
            raise Conflict("Another configuration version was created concurrently; retry.")
        audit.record(
            "tenant.config.version_created",
            request=request,
            actor=user,
            target=config,
            data={"version": config.version, "changed": sorted(clean)},
        )
    return config


def ensure_membership(user, role, *, status=MembershipStatus.ACTIVE):
    tenant = require_tenant()
    membership, _ = TenantMembership.objects.get_or_create(tenant=tenant, user=user, role=role, defaults={"status": status})
    return membership


def active_roles(user):
    return frozenset(TenantMembership.objects.filter(user=user, status=MembershipStatus.ACTIVE).values_list("role", flat=True))
