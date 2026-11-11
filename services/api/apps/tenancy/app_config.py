"""Settings the apps read from the server (D051).

The apps keep the last copy on the phone and re-read it when the version changes: every API response carries
`X-RideFlow-Config: <version>`, and the events socket pushes `{"type": "config"}` when the operator changes anything.
"""

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction
from django.utils import timezone

from apps.core.context import tenant_context

from .policy import PARAMS, current_policy

HEADER = "X-RideFlow-Config"

# Existing settings the apps also need, besides the `app.*` group.
SHARED_KEYS = (
    "fare.bid_step_minor",
    "fare.rider_min_pct",
    "bids.expiry_seconds",
    "match.driver_confirm_timeout_seconds",
    "presence.stale_seconds",
    "rides.bidding_timeout_seconds",
    "rides.evidence_ping_interval_seconds",
    "cancellation.free_after_match_seconds",
    "noshow.min_wait_seconds",
    "ratings.window_days",
    "trust.min_sample",
    "safety.emergency_phone",
)


def tenant_group(tenant_id):
    return f"tenant-config-{tenant_id}"


def version_of(tenant):
    """Changes whenever the operator's details change or a settings version takes effect (scheduled ones included)."""
    from .models import TenantConfig

    with tenant_context(tenant):
        latest = (
            TenantConfig.all_tenants.filter(tenant=tenant, effective_from__lte=timezone.now())
            .order_by("-version")
            .values_list("version", flat=True)
            .first()
        )
    return f"{latest or 0}.{int(tenant.updated_at.timestamp())}"


def _map_center(tenant):
    from apps.geo.models import City

    city = City.all_tenants.filter(tenant=tenant, is_active=True).order_by("created_at").first()
    if city is None or city.center is None:
        return None
    return {"lat": city.center.y, "lng": city.center.x}


def payload(tenant):
    with tenant_context(tenant):
        policy = current_policy(tenant)
        center = _map_center(tenant)
    settings = {key: policy[key] for key in PARAMS if key.startswith("app.")}
    settings.update({key: policy[key] for key in SHARED_KEYS})
    return {
        "version": version_of(tenant),
        "region": {
            "operator_name": tenant.name,
            "country": tenant.country,
            "currency": tenant.currency,
            "currency_symbol": tenant.currency_symbol or tenant.currency,
            "currency_minor_units": tenant.currency_minor_units,
            "distance_unit": tenant.distance_unit,
            "phone_country_code": tenant.phone_country_code,
            "time_zone": tenant.time_zone,
            "locale": tenant.locale,
            "map_center": center,
        },
        "settings": settings,
    }


def announce(tenant):
    """Tells connected apps to re-read their settings, after the change is committed. Best effort: the response
    header and the apps' periodic check cover anyone it misses."""

    def send():
        layer = get_channel_layer()
        if layer is None:
            return
        try:
            async_to_sync(layer.group_send)(tenant_group(tenant.pk), {"type": "config.changed", "version": version_of(tenant)})
        except Exception:  # noqa: BLE001 - delivery is a hint only
            pass

    transaction.on_commit(send)
