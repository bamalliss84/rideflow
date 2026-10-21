"""Tenant policy parameters (D017, ADR-0003).

Every business parameter lives here with its default, bounds and provenance. Values marked
`PROVISIONAL` are safe placeholders pending owner approval (see docs/OPEN_DECISIONS.md); they are
tenant-configurable and must be reviewed before a real pilot. Nothing here hardcodes a city.
"""

from dataclasses import dataclass

from django.utils import timezone
from rest_framework.exceptions import ValidationError

APPROVED = "APPROVED"
PROPOSED = "PROPOSED"  # proposed in the decision log, awaiting owner approval
PROVISIONAL = "PROVISIONAL"  # engineering placeholder, no documented value yet


@dataclass(frozen=True)
class Param:
    default: object
    kind: type
    min: float | None = None
    max: float | None = None
    status: str = PROVISIONAL
    source: str = ""


PARAMS = {
    # Fare guidance (indicative range only, never binding; D004)
    "fare.base_minor": Param(50000, int, 0, 10**9, PROVISIONAL, "no fare data yet; tenant must configure"),
    "fare.per_km_minor": Param(20000, int, 0, 10**9, PROVISIONAL, "no fare data yet; tenant must configure"),
    "fare.range_pct": Param(20, int, 0, 100, PROVISIONAL, "spread of indicative range"),
    # Dispatch waves (BUSINESS_RULES §2: 5–10 per wave)
    "dispatch.wave_size": Param(7, int, 1, 50, PROPOSED, "BUSINESS_RULES §2 (5–10)"),
    "dispatch.initial_radius_m": Param(3000, int, 100, 50000, PROVISIONAL, ""),
    "dispatch.radius_step_m": Param(2000, int, 0, 50000, PROVISIONAL, ""),
    "dispatch.max_waves": Param(3, int, 1, 20, PROVISIONAL, ""),
    # Bids (D004)
    "bids.expiry_seconds": Param(120, int, 15, 3600, PROVISIONAL, ""),
    "bids.max_per_driver_per_ride": Param(3, int, 1, 20, PROVISIONAL, "bid spam limit (BUSINESS_RULES §10)"),
    "bids.max_open_per_driver": Param(5, int, 1, 50, PROVISIONAL, "bid spam limit (BUSINESS_RULES §10)"),
    "rides.bidding_timeout_seconds": Param(900, int, 60, 7200, PROVISIONAL, "unmatched request auto-expiry"),
    "rides.evidence_ping_interval_seconds": Param(15, int, 1, 600, PROVISIONAL, "location evidence sampling"),
    "match.driver_confirm_timeout_seconds": Param(60, int, 10, 600, PROVISIONAL, "D012 resolved: confirmation required"),
    # Cancellation / no-show (D006 approved principle; D010 values proposed)
    "cancellation.free_after_match_seconds": Param(120, int, 0, 3600, PROPOSED, "D010 / BUSINESS_RULES §3"),
    "noshow.min_wait_seconds": Param(300, int, 60, 3600, PROPOSED, "D010"),
    "noshow.geofence_m": Param(200, int, 20, 2000, PROPOSED, "D010"),
    "noshow.max_accuracy_m": Param(100, int, 5, 1000, PROVISIONAL, "GPS accuracy above this is not evidence"),
    "noshow.require_contact_attempt": Param(True, bool, None, None, APPROVED, "BUSINESS_RULES §3"),
    # Presence / location
    "presence.stale_seconds": Param(120, int, 15, 3600, PROVISIONAL, ""),
    # Ratings and trust (D006 approved; D011 weights proposed)
    "ratings.window_days": Param(7, int, 1, 90, PROVISIONAL, ""),
    "ratings.prior_mean": Param(4.5, float, 1, 5, PROVISIONAL, "Bayesian prior (BUSINESS_RULES §4)"),
    "ratings.prior_weight": Param(5, int, 0, 100, PROVISIONAL, "Bayesian prior weight"),
    "trust.min_sample": Param(5, int, 0, 1000, PROVISIONAL, "minimum completed rides before a tier is shown"),
    "trust.driver_weights": Param(
        {"ratings": 30, "completion": 20, "cancellation": 20, "punctuality": 10, "complaints": 10, "conduct": 10},
        dict,
        None,
        None,
        PROPOSED,
        "D011 / 02_BUSINESS_POLICY",
    ),
    "trust.rider_weights": Param(
        {"ratings": 25, "attendance": 30, "cancellation": 20, "price_compliance": 15, "complaints": 10},
        dict,
        None,
        None,
        PROPOSED,
        "D011 / 02_BUSINESS_POLICY",
    ),
    "trust.tier_thresholds": Param(
        {"silver": 60, "gold": 75, "diamond": 90}, dict, None, None, PROVISIONAL, "D011 tiers; thresholds unset"
    ),
    "trust.punctuality_grace_seconds": Param(300, int, 0, 3600, PROVISIONAL, ""),
    # Enforcement ladder (D011 proposed; rolling 30 days)
    "enforcement.window_days": Param(30, int, 1, 365, PROPOSED, "D011"),
    "enforcement.level3_restriction_hours": Param(24, int, 0, 720, PROPOSED, "D011"),
    "enforcement.level4_restriction_hours": Param(72, int, 0, 720, PROPOSED, "D011"),
    "appeals.window_days": Param(7, int, 1, 90, PROVISIONAL, "appeal window not yet decided"),
    "disputes.window_days": Param(7, int, 1, 90, PROVISIONAL, ""),
    # Driver eligibility and subscriptions (D003 approved; D009 prices proposed)
    "drivers.required_documents": Param(
        ["national_id", "driving_license", "vehicle_registration"],
        list,
        None,
        None,
        PROVISIONAL,
        "D013 legal list pending",
    ),
    "subscriptions.required_for_online": Param(True, bool, None, None, APPROVED, "D003 driver subscription model"),
    "subscriptions.grace_days": Param(0, int, 0, 30, PROVISIONAL, ""),
    "subscriptions.dual_approval": Param(False, bool, None, None, PROPOSED, "maker-checker preferred (BUSINESS_RULES §8)"),
    "subscriptions.founder_trial_max_drivers": Param(100, int, 0, 100000, PROPOSED, "D009"),
    # Rewards and compensation (D011 proposed, D015 open) - disabled until approved
    "rewards.renewal_discount_enabled": Param(False, bool, None, None, PROPOSED, "D011"),
    "rewards.renewal_discount_pct": Param(10, int, 0, 50, PROPOSED, "D011 (10–15%)"),
    "rewards.min_tier": Param("gold", str, None, None, PROVISIONAL, ""),
    "compensation.enabled": Param(False, bool, None, None, PROVISIONAL, "D015 OPEN: disabled until approved"),
    "compensation.days_per_verified_no_show": Param(0, int, 0, 30, PROVISIONAL, "D015 OPEN"),
    "compensation.max_days_per_driver_month": Param(0, int, 0, 31, PROVISIONAL, "D015 OPEN"),
    "compensation.tenant_monthly_budget_days": Param(0, int, 0, 100000, PROVISIONAL, "D015 OPEN"),
    # Tenant suspension (OD-08 proposed)
    "tenant.block_new_rides_when_suspended": Param(True, bool, None, None, PROPOSED, "OD-08"),
}

DOCUMENT_TYPES = {"national_id", "driving_license", "vehicle_registration", "vehicle_photo", "driver_photo", "insurance"}


def defaults():
    return {key: param.default for key, param in PARAMS.items()}


def validate_overrides(overrides):
    if not isinstance(overrides, dict):
        raise ValidationError({"params": "Must be an object of parameter overrides."})
    errors = {}
    clean = {}
    for key, value in overrides.items():
        param = PARAMS.get(key)
        if param is None:
            errors[key] = "Unknown policy parameter."
            continue
        if param.kind is float and isinstance(value, int) and not isinstance(value, bool):
            value = float(value)
        if param.kind is int and isinstance(value, bool) or not isinstance(value, param.kind):
            errors[key] = f"Expected {param.kind.__name__}."
            continue
        if param.min is not None and value < param.min or param.max is not None and value > param.max:
            errors[key] = f"Must be between {param.min} and {param.max}."
            continue
        if key.endswith("_weights"):
            if set(value) != set(param.default) or any(not isinstance(v, int) or v < 0 for v in value.values()):
                errors[key] = f"Must define non-negative integer weights for {sorted(param.default)}."
                continue
            if sum(value.values()) <= 0:
                errors[key] = "Weights must not all be zero."
                continue
        if key == "trust.tier_thresholds":
            if set(value) != {"silver", "gold", "diamond"} or not (0 <= value["silver"] <= value["gold"] <= value["diamond"] <= 100):
                errors[key] = "Requires 0 <= silver <= gold <= diamond <= 100."
                continue
        if key == "drivers.required_documents" and not set(value) <= DOCUMENT_TYPES:
            errors[key] = f"Document types must be among {sorted(DOCUMENT_TYPES)}."
            continue
        clean[key] = value
    if errors:
        raise ValidationError({"params": errors})
    return clean


@dataclass(frozen=True)
class PolicySnapshot:
    version: int
    params: dict

    def __getitem__(self, key):
        return self.params[key]


def current_policy(tenant=None):
    """Effective policy for the tenant (latest version whose effective_from <= now)."""
    from apps.core.context import require_tenant

    from .models import TenantConfig

    tenant = tenant or require_tenant()
    config = TenantConfig.all_tenants.filter(tenant=tenant, effective_from__lte=timezone.now()).order_by("-version").first()
    params = defaults()
    if config is None:
        return PolicySnapshot(version=0, params=params)
    params.update(config.params)
    return PolicySnapshot(version=config.version, params=params)


def describe():
    return [
        {
            "key": key,
            "default": p.default,
            "type": p.kind.__name__,
            "min": p.min,
            "max": p.max,
            "status": p.status,
            "source": p.source,
        }
        for key, p in PARAMS.items()
    ]
