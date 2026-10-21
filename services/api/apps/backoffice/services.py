import statistics
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db import transaction
from django.db.models import Count, OuterRef, Q, Subquery, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone

from apps.accounts.models import User
from apps.core import audit
from apps.core.context import tenant_context
from apps.core.exceptions import BusinessRuleViolation
from apps.tenancy.models import AppType, MembershipStatus, Role, Tenant, TenantApplication, TenantMembership

# ---------------------------------------------------------------- platform provisioning


def provision_tenant(*, data, actor, request=None):
    with transaction.atomic():
        tenant = Tenant.objects.create(**data)
        for app_type, label in ((AppType.RIDER, "Rider app"), (AppType.DRIVER, "Driver app"), (AppType.ADMIN, "Admin web")):
            TenantApplication.objects.create(tenant=tenant, app_type=app_type, name=f"{tenant.name} {label}")
        audit.record(
            "platform.tenant_created",
            request=request,
            actor=actor,
            target=tenant,
            tenant_id=tenant.pk,
            data={"slug": tenant.slug, "currency": tenant.currency},
        )
    return tenant


def set_tenant_status(tenant, status, *, actor, request=None):
    tenant.status = status
    tenant.save(update_fields=["status", "updated_at"])
    audit.record(f"platform.tenant_{status}", request=request, actor=actor, target=tenant, tenant_id=tenant.pk)
    return tenant


def create_tenant_admin(tenant, *, phone, full_name, role, actor, request=None):
    """Platform admins provision the first operator admin; they get no tenant data access themselves."""
    with transaction.atomic():
        user = User.objects.filter(phone=phone).first() or User.objects.create_user(phone, full_name=full_name)
        with tenant_context(tenant):
            membership, created = TenantMembership.objects.get_or_create(
                user=user, role=role, tenant=tenant, defaults={"status": MembershipStatus.ACTIVE}
            )
            audit.record(
                "platform.tenant_admin_created",
                request=request,
                actor=actor,
                target=membership,
                data={"role": role, "created": created},
            )
    return membership


# ---------------------------------------------------------------- tenant members


def invite_member(*, phone, full_name, role, actor_roles, actor, request=None):
    if role == Role.OWNER and "owner" not in actor_roles:
        raise BusinessRuleViolation("Only owners can add owners.", code="owner_required")
    user = User.objects.filter(phone=phone).first() or User.objects.create_user(phone, full_name=full_name)
    membership, created = TenantMembership.objects.get_or_create(user=user, role=role, defaults={"status": MembershipStatus.ACTIVE})
    if not created and membership.status != MembershipStatus.ACTIVE:
        membership.status = MembershipStatus.ACTIVE
        membership.save(update_fields=["status", "updated_at"])
    audit.record("tenant.member_added", request=request, actor=actor, target=membership, data={"role": role})
    return membership


def set_member_status(membership, status, *, actor, actor_roles, request=None):
    if membership.user_id == actor.pk:
        raise BusinessRuleViolation("You cannot change your own membership.", code="self_change")
    if membership.role == Role.OWNER and "owner" not in actor_roles:
        raise BusinessRuleViolation("Only owners can change owners.", code="owner_required")
    if membership.role == Role.DRIVER and status == MembershipStatus.SUSPENDED:
        from apps.drivers.models import DriverProfile

        DriverProfile.objects.filter(user=membership.user).update(is_online=False)
    membership.status = status
    membership.save(update_fields=["status", "updated_at"])
    audit.record("tenant.member_status", request=request, actor=actor, target=membership, data={"status": status})
    return membership


# ---------------------------------------------------------------- metrics & reports


def _range(date_from=None, date_to=None):
    date_to = date_to or timezone.now()
    date_from = date_from or date_to - timedelta(days=7)
    if date_from > date_to:
        raise BusinessRuleViolation("date_from must be before date_to.", code="invalid_range")
    if date_to - date_from > timedelta(days=366):
        raise BusinessRuleViolation("Range is limited to 366 days.", code="range_too_large")
    return date_from, date_to


def _ratio(a, b):
    return round(a / b, 4) if b else None


def _median(values):
    return round(statistics.median(values), 1) if values else None


def dashboard_metrics(tenant, date_from=None, date_to=None):
    from apps.drivers.models import DriverProfile
    from apps.rides.models import Bid, Ride, RideStatus
    from apps.subscriptions.models import ClaimStatus, DepositClaim, DriverSubscription
    from apps.tenancy.policy import current_policy
    from apps.trust.models import Appeal, AppealStatus, Dispute, DisputeStatus, Violation, ViolationStatus

    date_from, date_to = _range(date_from, date_to)
    policy = current_policy()
    now = timezone.now()
    fresh = now - timedelta(seconds=policy["presence.stale_seconds"])

    drivers = DriverProfile.objects.aggregate(
        total=Count("id"),
        approved=Count("id", filter=Q(status="approved")),
        under_review=Count("id", filter=Q(status="under_review")),
        online=Count("id", filter=Q(is_online=True, location__server_ts__gte=fresh)),
    )
    active_subs = (
        DriverSubscription.objects.filter(is_revoked=False, starts_at__lte=now, ends_at__gte=now).values("driver").distinct().count()
    )

    rides = Ride.objects.filter(created_at__gte=date_from, created_at__lt=date_to)
    counts = rides.aggregate(
        requested=Count("id"),
        dispatched=Count("id", filter=Q(wave_count__gt=0)),
        matched=Count("id", filter=Q(assigned_at__isnull=False)),
        completed=Count("id", filter=Q(completed_at__isnull=False)),
        cancelled=Count("id", filter=Q(status=RideStatus.CANCELLED)),
        cancelled_after_match=Count("id", filter=Q(status=RideStatus.CANCELLED, assigned_at__isnull=False)),
        cancelled_by_rider=Count("id", filter=Q(status=RideStatus.CANCELLED, cancelled_by_role="rider")),
        cancelled_by_driver=Count("id", filter=Q(status=RideStatus.CANCELLED, cancelled_by_role="driver")),
        expired=Count("id", filter=Q(status=RideStatus.CANCELLED, cancelled_by_role="system")),
        no_show=Count("id", filter=Q(status=RideStatus.NO_SHOW)),
        disputed=Count("id", filter=Q(status=RideStatus.DISPUTED)),
        fare_total_minor=Sum("agreed_fare_minor", filter=Q(completed_at__isnull=False)),
    )
    with_bid = rides.filter(bids__isnull=False).distinct().count()
    first_bid_delays = []
    first_bid_sq = Subquery(Bid.objects.filter(ride=OuterRef("pk")).order_by("created_at").values("created_at")[:1])
    for created_at, first_bid in rides.annotate(first_bid=first_bid_sq).values_list("created_at", "first_bid"):
        if first_bid:
            first_bid_delays.append((first_bid - created_at).total_seconds())
    arrival_delays = [
        (arrived - assigned).total_seconds()
        for assigned, arrived in rides.filter(assigned_at__isnull=False, arrived_at__isnull=False).values_list(
            "assigned_at", "arrived_at"
        )
    ]
    repeat_riders = rides.filter(completed_at__isnull=False).values("rider").annotate(n=Count("id")).filter(n__gte=2).count()
    return {
        "range": {"from": date_from, "to": date_to},
        "currency": tenant.currency,
        "drivers": {**drivers, "with_active_subscription": active_subs},
        "rides": {**counts, "with_bids": with_bid, "fare_total_minor": counts["fare_total_minor"] or 0},
        "rates": {
            "bid_coverage": _ratio(with_bid, counts["dispatched"]),
            "match_rate": _ratio(counts["matched"], counts["requested"]),
            "completion_rate": _ratio(counts["completed"], counts["matched"]),
            "cancellation_after_match_rate": _ratio(counts["cancelled_after_match"], counts["matched"]),
            "no_show_rate": _ratio(counts["no_show"], counts["matched"]),
        },
        "timing_seconds": {
            "median_time_to_first_bid": _median(first_bid_delays),
            "median_assignment_to_arrival": _median(arrival_delays),
        },
        "riders": {"repeat_riders": repeat_riders, "unique_riders": rides.values("rider").distinct().count()},
        "queues": {
            "drivers_under_review": drivers["under_review"],
            "deposit_claims_pending": DepositClaim.objects.filter(
                status__in=[ClaimStatus.SUBMITTED, ClaimStatus.FIRST_APPROVED]
            ).count(),
            "disputes_open": Dispute.objects.filter(status__in=[DisputeStatus.OPEN, DisputeStatus.UNDER_REVIEW]).count(),
            "safety_disputes_open": Dispute.objects.filter(
                is_safety=True, status__in=[DisputeStatus.OPEN, DisputeStatus.UNDER_REVIEW]
            ).count(),
            "violations_pending_review": Violation.objects.filter(status=ViolationStatus.PENDING_REVIEW).count(),
            "appeals_pending": Appeal.objects.filter(status=AppealStatus.PENDING).count(),
        },
    }


def rides_daily_report(tenant, date_from=None, date_to=None):
    from apps.rides.models import Ride, RideStatus

    date_from, date_to = _range(date_from, date_to)
    tz = ZoneInfo(tenant.time_zone)
    rows = (
        Ride.objects.filter(created_at__gte=date_from, created_at__lt=date_to)
        .annotate(day=TruncDate("created_at", tzinfo=tz))
        .values("day")
        .annotate(
            requested=Count("id"),
            matched=Count("id", filter=Q(assigned_at__isnull=False)),
            completed=Count("id", filter=Q(completed_at__isnull=False)),
            cancelled=Count("id", filter=Q(status=RideStatus.CANCELLED)),
            no_show=Count("id", filter=Q(status=RideStatus.NO_SHOW)),
            fare_total_minor=Sum("agreed_fare_minor", filter=Q(completed_at__isnull=False)),
        )
        .order_by("day")
    )
    return {
        "range": {"from": date_from, "to": date_to},
        "time_zone": tenant.time_zone,
        "currency": tenant.currency,
        "rows": [{**r, "fare_total_minor": r["fare_total_minor"] or 0} for r in rows],
    }


def subscriptions_report(tenant, date_from=None, date_to=None):
    from apps.subscriptions.models import DepositClaim

    date_from, date_to = _range(date_from, date_to)
    claims = DepositClaim.objects.filter(created_at__gte=date_from, created_at__lt=date_to)
    by_status = {row["status"]: row["n"] for row in claims.values("status").annotate(n=Count("id"))}
    approved_total = claims.filter(status="approved").aggregate(s=Sum("amount_minor"))["s"] or 0
    by_plan = list(
        claims.filter(status="approved")
        .values("plan__code", "plan__name")
        .annotate(n=Count("id"), total_minor=Sum("amount_minor"))
        .order_by("plan__code")
    )
    return {
        "range": {"from": date_from, "to": date_to},
        "currency": tenant.currency,
        "claims_by_status": by_status,
        "approved_total_minor": approved_total,
        "approved_by_plan": by_plan,
    }
