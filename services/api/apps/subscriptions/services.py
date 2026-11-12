import secrets
import time
from datetime import timedelta

from django.db import IntegrityError, connection, transaction
from django.db.models import Max, Sum
from django.utils import timezone

from apps.core import audit
from apps.core.context import require_tenant
from apps.core.exceptions import BusinessRuleViolation, Conflict
from apps.tenancy.policy import current_policy

from .models import (
    ClaimStatus,
    DepositClaim,
    DriverSubscription,
    LedgerEntryType,
    SubscriptionLedgerEntry,
    SubscriptionPlan,
    SubscriptionReminder,
    SubscriptionSource,
)


def active_subscription(driver, policy=None, at=None):
    policy = policy or current_policy()
    at = at or timezone.now()
    grace = timedelta(days=policy["subscriptions.grace_days"])
    return (
        DriverSubscription.objects.filter(driver=driver, is_revoked=False, starts_at__lte=at, ends_at__gte=at - grace)
        .order_by("-ends_at")
        .first()
    )


def has_entitlement(driver, policy=None):
    return active_subscription(driver, policy) is not None


def _extend(driver, *, days, plan=None, source, claim=None):
    now = timezone.now()
    latest_end = DriverSubscription.objects.filter(driver=driver, is_revoked=False).aggregate(m=Max("ends_at"))["m"]
    start = max(now, latest_end) if latest_end else now
    return DriverSubscription.objects.create(
        driver=driver, plan=plan, starts_at=start, ends_at=start + timedelta(days=days), source=source, claim=claim
    )


def renewal_discount_pct(driver, policy=None):
    """Verified good-conduct renewal discount (D011 PROPOSED; disabled by default via policy)."""
    policy = policy or current_policy()
    if not policy["rewards.renewal_discount_enabled"]:
        return 0
    from apps.trust.services import reward_eligibility

    return policy["rewards.renewal_discount_pct"] if reward_eligibility(driver.user, "driver", policy)["eligible"] else 0


def expected_amount(plan, driver, policy=None):
    pct = renewal_discount_pct(driver, policy)
    return plan.price_minor - (plan.price_minor * pct) // 100, pct


def submit_claim(driver, *, plan, deposit_account, amount_minor, reference, deposited_on, receipt, content_type, sha256, request=None):
    tenant = require_tenant()
    if plan.is_trial or not plan.is_active:
        raise BusinessRuleViolation("This plan cannot be paid by deposit.", code="plan_invalid")
    if not deposit_account.is_active:
        raise BusinessRuleViolation("Deposit account is not active.", code="deposit_account_inactive")
    expected, pct = expected_amount(plan, driver)
    if amount_minor != expected:
        raise BusinessRuleViolation(
            {"amount_minor": f"Deposit must equal {expected} {tenant.currency} (minor units)."}, code="amount_mismatch"
        )
    reference = reference.strip().upper()
    if DepositClaim.objects.filter(reference=reference).exists():
        raise Conflict("This deposit reference was already submitted.", code="duplicate_reference")
    if DepositClaim.objects.filter(receipt_sha256=sha256).exists():
        raise Conflict("This receipt file was already submitted.", code="duplicate_receipt")
    try:
        with transaction.atomic():
            claim = DepositClaim.objects.create(
                driver=driver,
                plan=plan,
                deposit_account=deposit_account,
                amount_minor=amount_minor,
                expected_amount_minor=expected,
                discount_pct=pct,
                currency=tenant.currency,
                reference=reference,
                deposited_on=deposited_on,
                receipt=receipt,
                receipt_content_type=content_type,
                receipt_sha256=sha256,
            )
    except IntegrityError:
        raise Conflict("Duplicate deposit reference or receipt.", code="duplicate_deposit")
    audit.record(
        "subscription.claim_submitted", request=request, target=claim, data={"reference": reference, "amount_minor": amount_minor}
    )
    from apps.notifications.services import notify_staff

    notify_staff("subscriptions.review", "staff.deposit_submitted", {"claim_id": str(claim.pk), "reference": reference})
    return claim


def _notify(driver, kind, payload):
    from apps.notifications.services import notify

    notify(driver.user, kind, payload)


def approve_claim(claim, reviewer, note="", request=None):
    """Maker-checker when policy requires two approvals; row lock prevents double approval (T5/T6)."""
    policy = current_policy()
    with transaction.atomic():
        claim = DepositClaim.objects.select_for_update().select_related("driver", "plan").get(pk=claim.pk)
        if claim.driver.user_id == reviewer.pk:
            raise BusinessRuleViolation("You cannot approve your own deposit.", code="self_approval")
        if claim.status in (ClaimStatus.APPROVED, ClaimStatus.REJECTED):
            raise Conflict(f"Claim already {claim.status}.", code="claim_decided")
        now = timezone.now()
        if policy["subscriptions.dual_approval"] and claim.status == ClaimStatus.SUBMITTED:
            claim.status = ClaimStatus.FIRST_APPROVED
            claim.first_approved_by = reviewer
            claim.first_approved_at = now
            claim.save(update_fields=["status", "first_approved_by", "first_approved_at", "updated_at"])
            audit.record("subscription.claim_first_approved", request=request, target=claim, data={"note": note})
            return claim
        if claim.status == ClaimStatus.FIRST_APPROVED and claim.first_approved_by_id == reviewer.pk:
            raise BusinessRuleViolation("A different reviewer must give the second approval.", code="same_approver")
        claim.status = ClaimStatus.APPROVED
        claim.decided_by = reviewer
        claim.decided_at = now
        claim.decision_note = note
        claim.save(update_fields=["status", "decided_by", "decided_at", "decision_note", "updated_at"])
        subscription = _extend(
            claim.driver, days=claim.plan.duration_days, plan=claim.plan, source=SubscriptionSource.DEPOSIT, claim=claim
        )
        SubscriptionLedgerEntry.objects.create(
            driver=claim.driver,
            entry_type=LedgerEntryType.SUBSCRIPTION_PAYMENT,
            amount_minor=claim.amount_minor,
            currency=claim.currency,
            days=claim.plan.duration_days,
            claim=claim,
            subscription=subscription,
            reference=claim.reference,
            created_by=reviewer,
        )
        if claim.discount_pct:
            SubscriptionLedgerEntry.objects.create(
                driver=claim.driver,
                entry_type=LedgerEntryType.DISCOUNT,
                amount_minor=claim.plan.price_minor - claim.expected_amount_minor,
                currency=claim.currency,
                claim=claim,
                note=f"{claim.discount_pct}% verified-conduct renewal discount",
                created_by=reviewer,
            )
        audit.record(
            "subscription.claim_approved",
            request=request,
            target=claim,
            data={"subscription_id": str(subscription.pk), "ends_at": subscription.ends_at.isoformat()},
        )
        _notify(claim.driver, "subscription.activated", {"claim_id": str(claim.pk), "ends_at": subscription.ends_at.isoformat()})
        _reward_referrer(claim, policy)
    return claim


def reject_claim(claim, reviewer, note, request=None):
    if not note:
        raise BusinessRuleViolation("A rejection reason is required.", code="reason_required")
    with transaction.atomic():
        claim = DepositClaim.objects.select_for_update().get(pk=claim.pk)
        if claim.status in (ClaimStatus.APPROVED, ClaimStatus.REJECTED):
            raise Conflict(f"Claim already {claim.status}.", code="claim_decided")
        claim.status = ClaimStatus.REJECTED
        claim.decided_by = reviewer
        claim.decided_at = timezone.now()
        claim.decision_note = note
        claim.save(update_fields=["status", "decided_by", "decided_at", "decision_note", "updated_at"])
        audit.record("subscription.claim_rejected", request=request, target=claim, data={"note": note})
        _notify(claim.driver, "subscription.claim_rejected", {"claim_id": str(claim.pk), "reason": note})
    return claim


def _tenant_lock(name):
    with connection.cursor() as cursor:
        cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", [f"{name}:{require_tenant().pk}"])


def start_trial(driver, request=None):
    """Founder trial (D009 PROPOSED values): once per driver, limited to the first N drivers of the tenant."""
    from apps.drivers.models import DriverStatus

    policy = current_policy()
    if driver.status != DriverStatus.APPROVED:
        raise BusinessRuleViolation("Only approved drivers can start the trial.", code="driver_not_approved")
    with transaction.atomic():
        _tenant_lock("founder-trial")
        plan = SubscriptionPlan.objects.filter(is_trial=True, is_active=True).order_by("sort_order").first()
        if plan is None:
            raise BusinessRuleViolation("No trial is offered.", code="trial_unavailable")
        granted = SubscriptionLedgerEntry.objects.filter(entry_type=LedgerEntryType.TRIAL_GRANT)
        if granted.filter(driver=driver).exists():
            raise Conflict("Trial already used.", code="trial_used")
        if granted.values("driver").distinct().count() >= policy["subscriptions.founder_trial_max_drivers"]:
            raise BusinessRuleViolation("Founder trial places are exhausted.", code="trial_exhausted")
        subscription = _extend(driver, days=plan.duration_days, plan=plan, source=SubscriptionSource.TRIAL)
        SubscriptionLedgerEntry.objects.create(
            driver=driver,
            entry_type=LedgerEntryType.TRIAL_GRANT,
            currency=require_tenant().currency,
            days=plan.duration_days,
            subscription=subscription,
            note=plan.name,
        )
        audit.record("subscription.trial_started", request=request, target=subscription)
    return subscription


def grant_compensation(driver, *, reason_ref, created_by=None):
    """No-show compensation as subscription days (D015 OPEN: only when the tenant enabled it with caps)."""
    policy = current_policy()
    days = policy["compensation.days_per_verified_no_show"]
    if not policy["compensation.enabled"] or days <= 0:
        return None
    with transaction.atomic():
        _tenant_lock("compensation")
        month_start = timezone.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        credits = SubscriptionLedgerEntry.objects.filter(entry_type=LedgerEntryType.COMPENSATION_CREDIT, created_at__gte=month_start)
        driver_used = credits.filter(driver=driver).aggregate(s=Sum("days"))["s"] or 0
        tenant_used = credits.aggregate(s=Sum("days"))["s"] or 0
        days = min(
            days,
            policy["compensation.max_days_per_driver_month"] - driver_used,
            policy["compensation.tenant_monthly_budget_days"] - tenant_used,
        )
        if days <= 0:
            return None
        subscription = _extend(driver, days=days, source=SubscriptionSource.COMPENSATION)
        entry = SubscriptionLedgerEntry.objects.create(
            driver=driver,
            entry_type=LedgerEntryType.COMPENSATION_CREDIT,
            currency=require_tenant().currency,
            days=days,
            subscription=subscription,
            reference=reason_ref,
            created_by=created_by,
        )
    return entry


# ---------------------------------------------------------------- D052: plans that sell themselves, reminders, invitations


def plan_values(plans):
    """Per-day price of each paid plan, its saving against the dearest per day, and the best value (D052).

    Worked out from the operator's own plans, so the app never needs numbers of its own."""
    paid = [p for p in plans if not p.is_trial and p.price_minor > 0 and p.duration_days > 0]
    per_day = {p.pk: p.price_minor / p.duration_days for p in paid}
    dearest = max(per_day.values(), default=0)
    best = min(paid, key=lambda p: (per_day[p.pk], -p.duration_days)) if len(paid) > 1 else None
    out = {}
    for p in plans:
        if p.pk not in per_day:
            out[p.pk] = {"per_day_minor": 0, "saving_pct": 0, "best_value": False}
            continue
        saving = int(round((dearest - per_day[p.pk]) * 100 / dearest)) if dearest else 0
        out[p.pk] = {
            "per_day_minor": int(round(per_day[p.pk])),
            "saving_pct": saving,
            "best_value": best is not None and p.pk == best.pk,
        }
    return out


def cover_ends_at(driver):
    """When the driver's paid or credited time runs out, counting renewals queued after the current one."""
    return DriverSubscription.objects.filter(driver=driver, is_revoked=False).aggregate(m=Max("ends_at"))["m"]


def earnings_last_days(driver, days=30):
    """Cash fares of completed trips in the last `days`, so the driver can weigh a plan against what it brings in."""
    from apps.rides.models import Ride, RideStatus

    since = timezone.now() - timedelta(days=days)
    rows = Ride.objects.filter(driver=driver, status=RideStatus.COMPLETED, completed_at__gte=since)
    agg = rows.aggregate(total=Sum("agreed_fare_minor"))
    return {"days": days, "trips": rows.count(), "earned_minor": agg["total"] or 0}


_REMINDERS_EVERY = 60
_last_reminders = {"at": 0.0}


def process_all_reminders(force=False):
    """Worker entry point, at most once a minute: reminds drivers before their cover ends and when it has ended."""
    if not force and time.monotonic() - _last_reminders["at"] < _REMINDERS_EVERY:
        return 0
    _last_reminders["at"] = time.monotonic()
    from apps.core.context import system_context, tenant_context
    from apps.tenancy.models import Tenant

    sent = 0
    with system_context():
        tenants = list(Tenant.objects.all())
    for tenant in tenants:
        with tenant_context(tenant):
            sent += send_reminders()
    return sent


def send_reminders(now=None):
    """For the current tenant. Only the nearest reminder due is sent, so a worker that was down doesn't send a burst."""
    policy = current_policy()
    now = now or timezone.now()
    days = sorted(policy["subscriptions.reminder_days"], reverse=True)
    horizon = now + timedelta(days=max(days, default=0))
    grace = timedelta(days=policy["subscriptions.grace_days"])
    ends = (
        DriverSubscription.objects.filter(is_revoked=False)
        .values("driver")
        .annotate(end=Max("ends_at"))
        .filter(end__lte=horizon, end__gte=now - max(grace, timedelta(days=1)))
    )
    sent = 0
    from apps.drivers.models import DriverProfile

    for row in ends:
        end = row["end"]
        if end > now:
            due = [d for d in days if end - timedelta(days=d) <= now]
            if not due:
                continue
            nearest = min(due)
            kind = f"before:{nearest}"
            payload = {"ends_at": end.isoformat(), "days_left": max(1, -(-int((end - now).total_seconds()) // 86400))}
            notify_kind = "subscription.expiring"
            skip = [f"before:{d}" for d in due if d != nearest]  # older ones that were never sent stay unsent
        else:
            kind, notify_kind, skip = "ended", "subscription.expired", []
            payload = {"ends_at": end.isoformat(), "grace_until": (end + grace).isoformat() if grace else None}
        if SubscriptionReminder.objects.filter(driver_id=row["driver"], ends_at=end, kind__in=[kind]).exists():
            continue
        with transaction.atomic():
            try:
                with transaction.atomic():
                    SubscriptionReminder.objects.create(driver_id=row["driver"], ends_at=end, kind=kind)
                    for k in skip:
                        SubscriptionReminder.objects.get_or_create(driver_id=row["driver"], ends_at=end, kind=k)
            except IntegrityError:
                continue  # another worker sent it
            driver = DriverProfile.objects.select_related("user").get(pk=row["driver"])
            _notify(driver, notify_kind, payload)
            sent += 1
    return sent


_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O or 1/I to misread


def referral_code(driver):
    """The driver's own code, made the first time it is asked for."""
    if driver.referral_code:
        return driver.referral_code
    for _ in range(10):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(6))
        try:
            with transaction.atomic():
                type(driver).objects.filter(pk=driver.pk, referral_code="").update(referral_code=code)
        except IntegrityError:
            continue
        driver.refresh_from_db(fields=["referral_code"])
        return driver.referral_code
    raise Conflict("Could not make a referral code; try again.", code="referral_code_busy")


def has_paid_plan(driver):
    return DriverSubscription.objects.filter(driver=driver, source=SubscriptionSource.DEPOSIT).exists()


def use_referral_code(driver, code, request=None):
    """A new driver says who invited them. Once, before their first paid plan, and never their own code."""
    from apps.drivers.models import DriverProfile

    code = (code or "").strip().upper()
    if driver.referred_by_id:
        raise Conflict("You already entered an invitation code.", code="referral_already_set")
    if has_paid_plan(driver):
        raise BusinessRuleViolation("Invitation codes are for drivers before their first plan.", code="referral_too_late")
    inviter = DriverProfile.objects.filter(referral_code=code).exclude(referral_code="").first() if code else None
    if inviter is None:
        raise BusinessRuleViolation("This invitation code is not valid.", code="referral_invalid")
    if inviter.pk == driver.pk:
        raise BusinessRuleViolation("You can't use your own code.", code="referral_self")
    updated = type(driver).objects.filter(pk=driver.pk, referred_by__isnull=True).update(referred_by=inviter)
    if not updated:
        raise Conflict("You already entered an invitation code.", code="referral_already_set")
    driver.referred_by = inviter
    audit.record("subscription.referral_used", request=request, target=driver, data={"inviter": str(inviter.pk)})
    return inviter


def referral_summary(driver, policy=None):
    from apps.drivers.models import DriverProfile

    policy = policy or current_policy()
    invited = DriverProfile.objects.filter(referred_by=driver)
    rewarded = SubscriptionLedgerEntry.objects.filter(driver=driver, entry_type=LedgerEntryType.REFERRAL_CREDIT)
    return {
        "code": referral_code(driver) if policy["rewards.referral_days"] > 0 else "",
        "reward_days": policy["rewards.referral_days"],
        "invited": invited.count(),
        "rewarded": rewarded.count(),
        "days_earned": rewarded.aggregate(s=Sum("days"))["s"] or 0,
        "can_enter_code": policy["rewards.referral_days"] > 0 and not driver.referred_by_id and not has_paid_plan(driver),
    }


def _reward_referrer(claim, policy):
    """Inside the approval: the inviter gets their days on the invitee's first paid plan, once per invitee."""
    driver = claim.driver
    days = policy["rewards.referral_days"]
    if days <= 0 or not driver.referred_by_id:
        return None
    if DriverSubscription.objects.filter(driver=driver, source=SubscriptionSource.DEPOSIT).exclude(claim=claim).exists():
        return None  # not the first paid plan
    reference = f"referral:{driver.pk}"
    if SubscriptionLedgerEntry.objects.filter(entry_type=LedgerEntryType.REFERRAL_CREDIT, reference=reference).exists():
        return None
    inviter = driver.referred_by
    subscription = _extend(inviter, days=days, source=SubscriptionSource.REFERRAL)
    entry = SubscriptionLedgerEntry.objects.create(
        driver=inviter,
        entry_type=LedgerEntryType.REFERRAL_CREDIT,
        currency=require_tenant().currency,
        days=days,
        subscription=subscription,
        reference=reference,
    )
    _notify(inviter, "subscription.referral_reward", {"days": days, "ends_at": subscription.ends_at.isoformat()})
    return entry
