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
