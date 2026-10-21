"""Trust & conduct. Principles (D006, BUSINESS_RULES §4-6): stars and objective commitment are separate;
no sanction from stars alone; incidents need human verification; restrictions need human activation;
every verified violation is appealable; no monetary fines."""

from datetime import timedelta

from django.db import IntegrityError, transaction
from django.db.models import Count, Sum
from django.http import Http404
from django.utils import timezone

from apps.core import audit
from apps.core.exceptions import BusinessRuleViolation, Conflict
from apps.notifications.services import notify, notify_staff
from apps.tenancy.policy import current_policy

from .models import (
    Appeal,
    AppealStatus,
    Dispute,
    DisputeCategory,
    DisputeNote,
    DisputeStatus,
    EnforcementAction,
    EnforcementStatus,
    EnforcementType,
    Rating,
    TrustSnapshot,
    Violation,
    ViolationKind,
    ViolationStatus,
)

METHOD_VERSION = "trust-v1-provisional"
TIER_ORDER = ["new", "bronze", "silver", "gold", "diamond"]

# ---------------------------------------------------------------- ratings


def rate_ride(ride_id, user, *, stars, tags=None, comment=""):
    from apps.rides.models import Ride, RideStatus

    policy = current_policy()
    with transaction.atomic():
        ride = Ride.objects.select_for_update(of=("self",)).filter(pk=ride_id).select_related("driver").first()
        if ride is None:
            raise Http404
        if ride.rider_id == user.pk:
            rater_role, ratee, ratee_role = "rider", ride.driver.user if ride.driver else None, "driver"
        elif ride.driver is not None and ride.driver.user_id == user.pk:
            rater_role, ratee, ratee_role = "driver", ride.rider, "rider"
        else:
            raise Http404
        if ride.completed_at is None or ride.status not in (RideStatus.COMPLETED, RideStatus.DISPUTED):
            raise Conflict("Only completed rides can be rated.", code="ride_not_completed")
        if timezone.now() > ride.completed_at + timedelta(days=policy["ratings.window_days"]):
            raise BusinessRuleViolation("The rating window has closed.", code="rating_window_closed")
        try:
            with transaction.atomic():
                rating = Rating.objects.create(
                    ride=ride,
                    rater=user,
                    ratee=ratee,
                    rater_role=rater_role,
                    ratee_role=ratee_role,
                    stars=stars,
                    tags=tags or [],
                    comment=comment,
                )
        except IntegrityError:
            raise Conflict("You already rated this ride.", code="already_rated")
        refresh_trust(ratee, ratee_role)
    return rating


# ---------------------------------------------------------------- trust score


def _bad_rate_complement(bad, total, weight):
    """1 - smoothed failure rate; new users start at 1.0 (no new-user penalty, R04-01)."""
    return 1.0 - (bad / (total + weight)) if total + weight > 0 else 1.0


def _smoothed_success(good, total, weight):
    return (good + weight) / (total + weight) if total + weight > 0 else 1.0


def compute_trust(user, role, policy=None):
    from apps.rides.models import Bid, BidStatus, Ride

    policy = policy or current_policy()
    prior_mean, weight = policy["ratings.prior_mean"], policy["ratings.prior_weight"]
    stats = Rating.objects.filter(ratee=user, ratee_role=role).aggregate(n=Count("id"), total=Sum("stars"))
    n, total_stars = stats["n"] or 0, stats["total"] or 0
    rating_avg = (prior_mean * weight + total_stars) / (weight + n) if weight + n else prior_mean
    ratings_component = (rating_avg - 1) / 4

    verified = Violation.objects.filter(subject=user, subject_role=role, status=ViolationStatus.VERIFIED)
    window_start = timezone.now() - timedelta(days=policy["enforcement.window_days"])
    upheld_against = Dispute.objects.filter(against=user, against_role=role, status=DisputeStatus.UPHELD)

    if role == "driver":
        rides = Ride.objects.filter(driver__user=user, assigned_at__isnull=False)
        assigned = rides.count()
        completed = rides.filter(completed_at__isnull=False).count()
        late_cancels = verified.filter(kind__in=[ViolationKind.DRIVER_LATE_CANCELLATION, ViolationKind.DRIVER_NO_ARRIVAL]).count()
        grace = timedelta(seconds=policy["trust.punctuality_grace_seconds"])
        arrived = 0
        on_time = 0
        accepted = {b.ride_id: b.eta_seconds for b in Bid.objects.filter(driver__user=user, status=BidStatus.ACCEPTED)}
        for ride_id, assigned_at, arrived_at in rides.filter(arrived_at__isnull=False).values_list("id", "assigned_at", "arrived_at"):
            arrived += 1
            eta = accepted.get(ride_id)
            if eta is not None and arrived_at - assigned_at <= timedelta(seconds=eta) + grace:
                on_time += 1
        components = {
            "ratings": ratings_component,
            "completion": _smoothed_success(completed, assigned, weight),
            "cancellation": _bad_rate_complement(late_cancels, assigned, weight),
            "punctuality": _smoothed_success(on_time, arrived, weight),
            "complaints": _bad_rate_complement(upheld_against.count(), max(completed, 1), weight),
            "conduct": 1.0 - min(1.0, verified.filter(reviewed_at__gte=window_start).count() / 4),
        }
        weights = policy["trust.driver_weights"]
        completion_rate = completed / assigned if assigned else None
    else:
        rides = Ride.objects.filter(rider=user)
        matched = rides.filter(assigned_at__isnull=False).count()
        completed = rides.filter(completed_at__isnull=False).count()
        components = {
            "ratings": ratings_component,
            "attendance": _bad_rate_complement(verified.filter(kind=ViolationKind.RIDER_NO_SHOW).count(), matched, weight),
            "cancellation": _bad_rate_complement(verified.filter(kind=ViolationKind.RIDER_LATE_CANCELLATION).count(), matched, weight),
            "price_compliance": _bad_rate_complement(
                upheld_against.filter(category=DisputeCategory.FARE).count(), max(completed, 1), weight
            ),
            "complaints": _bad_rate_complement(
                upheld_against.exclude(category=DisputeCategory.FARE).count(), max(completed, 1), weight
            ),
        }
        weights = policy["trust.rider_weights"]
        completion_rate = completed / matched if matched else None
    total_weight = sum(weights.values()) or 1
    score = round(100 * sum(weights[k] * components[k] for k in weights) / total_weight, 1)
    thresholds = policy["trust.tier_thresholds"]
    if completed < policy["trust.min_sample"]:
        tier = "new"
    elif score >= thresholds["diamond"]:
        tier = "diamond"
    elif score >= thresholds["gold"]:
        tier = "gold"
    elif score >= thresholds["silver"]:
        tier = "silver"
    else:
        tier = "bronze"
    return {
        "score": score,
        "rating_avg": round(rating_avg, 2),
        "rating_count": n,
        "completed_rides": completed,
        "completion_rate": round(completion_rate, 3) if completion_rate is not None else None,
        "tier": tier,
        "components": {k: round(v, 4) for k, v in components.items()},
        "method_version": METHOD_VERSION,
        "config_version": policy.version,
    }


def refresh_trust(user, role):
    if user is None:
        return None
    data = compute_trust(user, role)
    snapshot, _ = TrustSnapshot.objects.update_or_create(user=user, role=role, defaults=data)
    return snapshot


def public_summary(user, role):
    snapshot = TrustSnapshot.objects.filter(user=user, role=role).first()
    if snapshot is None:
        snapshot = refresh_trust(user, role)
    return {
        "rating_avg": snapshot.rating_avg,
        "rating_count": snapshot.rating_count,
        "completed_rides": snapshot.completed_rides,
        "completion_rate": snapshot.completion_rate,
        "tier": snapshot.tier,
        "score": snapshot.score,
    }


# ---------------------------------------------------------------- incidents & enforcement


def record_incident(subject, role, kind, *, ride=None, evidence=None, reported_by=None, dispute=None):
    violation = Violation.objects.create(
        subject=subject, subject_role=role, kind=kind, ride=ride, dispute=dispute, evidence=evidence or {}, reported_by=reported_by
    )
    notify(subject, "trust.incident_recorded", {"violation_id": str(violation.pk), "kind": kind, "status": violation.status})
    notify_staff("violations.review", "staff.incident_recorded", {"violation_id": str(violation.pk), "kind": kind})
    return violation


def _ladder(violation, reviewer, policy):
    """Rolling-window ladder (D011 PROPOSED). Only warnings/commitment effects activate automatically;
    restrictions are proposed for human activation; safety goes to human escalation."""
    if violation.kind == ViolationKind.SAFETY:
        return EnforcementAction.objects.create(
            subject=violation.subject,
            subject_role=violation.subject_role,
            violation=violation,
            level=0,
            action_type=EnforcementType.ESCALATION,
            status=EnforcementStatus.PROPOSED,
            reason="Safety incident: immediate human escalation required.",
        )
    window_start = timezone.now() - timedelta(days=policy["enforcement.window_days"])
    count = Violation.objects.filter(
        subject=violation.subject, subject_role=violation.subject_role, status=ViolationStatus.VERIFIED, reviewed_at__gte=window_start
    ).count()
    level = min(max(count, 1), 4)
    now = timezone.now()
    if level == 1:
        kind, status, hours = EnforcementType.WARNING, EnforcementStatus.ACTIVE, 0
    elif level == 2:
        kind, status, hours = EnforcementType.COMMITMENT_EFFECT, EnforcementStatus.ACTIVE, 0
    else:
        kind, status = EnforcementType.RESTRICTION, EnforcementStatus.PROPOSED
        hours = policy["enforcement.level3_restriction_hours" if level == 3 else "enforcement.level4_restriction_hours"]
    return EnforcementAction.objects.create(
        subject=violation.subject,
        subject_role=violation.subject_role,
        violation=violation,
        level=level,
        action_type=kind,
        status=status,
        duration_hours=hours,
        starts_at=now if status == EnforcementStatus.ACTIVE else None,
        decided_by=reviewer if status == EnforcementStatus.ACTIVE else None,
        reason=f"{count} verified incident(s) in {policy['enforcement.window_days']} days",
    )


def review_violation(violation, *, verify, reviewer, note, request=None):
    policy = current_policy()
    if not note:
        raise BusinessRuleViolation("A review note is required.", code="reason_required")
    with transaction.atomic():
        violation = Violation.objects.select_for_update().get(pk=violation.pk)
        if violation.status != ViolationStatus.PENDING_REVIEW:
            raise Conflict(f"Violation already {violation.status}.", code="already_reviewed")
        if violation.subject_id == reviewer.pk:
            raise BusinessRuleViolation("You cannot review your own case.", code="self_review")
        violation.status = ViolationStatus.VERIFIED if verify else ViolationStatus.DISMISSED
        violation.reviewed_by = reviewer
        violation.reviewed_at = timezone.now()
        violation.review_note = note
        violation.save()
        action = None
        if verify:
            action = _ladder(violation, reviewer, policy)
            if violation.kind == ViolationKind.RIDER_NO_SHOW and violation.ride and violation.ride.driver:
                from apps.subscriptions.services import grant_compensation

                grant_compensation(violation.ride.driver, reason_ref=f"violation:{violation.pk}", created_by=reviewer)
        refresh_trust(violation.subject, violation.subject_role)
        audit.record(
            "trust.violation_reviewed",
            request=request,
            target=violation,
            data={"verified": verify, "enforcement": action.action_type if action else None},
        )
        notify(
            violation.subject,
            "trust.violation_reviewed",
            {
                "violation_id": str(violation.pk),
                "status": violation.status,
                "appeal_until": (violation.reviewed_at + timedelta(days=policy["appeals.window_days"])).isoformat(),
            },
        )
    return violation, action


def activate_enforcement(action, reviewer, request=None):
    with transaction.atomic():
        action = EnforcementAction.objects.select_for_update().get(pk=action.pk)
        if action.status != EnforcementStatus.PROPOSED:
            raise Conflict(f"Action is {action.status}.", code="invalid_transition")
        if action.violation.status != ViolationStatus.VERIFIED:
            raise Conflict("Violation is no longer verified.", code="violation_not_verified")
        now = timezone.now()
        action.status = EnforcementStatus.ACTIVE
        action.starts_at = now
        action.ends_at = now + timedelta(hours=action.duration_hours) if action.duration_hours else None
        action.decided_by = reviewer
        action.save()
        audit.record("trust.enforcement_activated", request=request, target=action)
        notify(
            action.subject,
            "trust.enforcement_active",
            {
                "action_id": str(action.pk),
                "type": action.action_type,
                "ends_at": action.ends_at.isoformat() if action.ends_at else None,
            },
        )
    return action


def revoke_enforcement(action, reviewer, note="", request=None):
    with transaction.atomic():
        action = EnforcementAction.objects.select_for_update().get(pk=action.pk)
        if action.status == EnforcementStatus.REVOKED:
            raise Conflict("Already revoked.", code="invalid_transition")
        action.status = EnforcementStatus.REVOKED
        action.decided_by = reviewer
        action.reason = (action.reason + f" | revoked: {note}")[:500]
        action.save()
        audit.record("trust.enforcement_revoked", request=request, target=action, data={"note": note})
    return action


def active_restriction(user, role):
    now = timezone.now()
    return (
        EnforcementAction.objects.filter(
            subject=user,
            subject_role=role,
            action_type=EnforcementType.RESTRICTION,
            status=EnforcementStatus.ACTIVE,
            starts_at__lte=now,
            ends_at__gt=now,
        )
        .order_by("-ends_at")
        .first()
    )


# ---------------------------------------------------------------- appeals


def file_appeal(violation, user, reason):
    policy = current_policy()
    if violation.subject_id != user.pk:
        raise Http404
    if violation.status not in (ViolationStatus.PENDING_REVIEW, ViolationStatus.VERIFIED):
        raise Conflict(f"Violation is {violation.status}.", code="not_appealable")
    reference = violation.reviewed_at or violation.created_at
    if timezone.now() > reference + timedelta(days=policy["appeals.window_days"]):
        raise BusinessRuleViolation("The appeal window has closed.", code="appeal_window_closed")
    try:
        with transaction.atomic():
            appeal = Appeal.objects.create(violation=violation, appellant=user, reason=reason)
    except IntegrityError:
        raise Conflict("An appeal is already pending.", code="appeal_pending")
    notify_staff("violations.review", "staff.appeal_filed", {"appeal_id": str(appeal.pk), "violation_id": str(violation.pk)})
    return appeal


def decide_appeal(appeal, *, uphold, reviewer, note, request=None):
    if not note:
        raise BusinessRuleViolation("A decision note is required.", code="reason_required")
    with transaction.atomic():
        appeal = Appeal.objects.select_for_update().select_related("violation").get(pk=appeal.pk)
        if appeal.status != AppealStatus.PENDING:
            raise Conflict(f"Appeal already {appeal.status}.", code="already_decided")
        violation = Violation.objects.select_for_update().get(pk=appeal.violation_id)
        if violation.reviewed_by_id == reviewer.pk:
            raise BusinessRuleViolation("A different reviewer must decide the appeal.", code="same_reviewer")
        appeal.status = AppealStatus.UPHELD if uphold else AppealStatus.REJECTED
        appeal.decided_by = reviewer
        appeal.decided_at = timezone.now()
        appeal.decision_note = note
        appeal.save()
        if uphold:
            violation.status = ViolationStatus.OVERTURNED
            violation.save(update_fields=["status", "updated_at"])
            EnforcementAction.objects.filter(violation=violation).exclude(status=EnforcementStatus.REVOKED).update(
                status=EnforcementStatus.REVOKED
            )
            refresh_trust(violation.subject, violation.subject_role)
        audit.record("trust.appeal_decided", request=request, target=appeal, data={"upheld": uphold})
        notify(appeal.appellant, "trust.appeal_decided", {"appeal_id": str(appeal.pk), "status": appeal.status})
    return appeal


# ---------------------------------------------------------------- disputes


def open_dispute(ride_id, user, *, category, description):
    from apps.rides.models import Ride
    from apps.rides.services import mark_disputed

    policy = current_policy()
    with transaction.atomic():
        ride = Ride.objects.select_for_update(of=("self",)).filter(pk=ride_id).select_related("driver").first()
        if ride is None:
            raise Http404
        if ride.rider_id == user.pk:
            role, against, against_role = "rider", ride.driver.user if ride.driver else None, "driver"
        elif ride.driver is not None and ride.driver.user_id == user.pk:
            role, against, against_role = "driver", ride.rider, "rider"
        else:
            raise Http404
        closed_at = ride.completed_at or ride.cancelled_at or ride.updated_at
        if timezone.now() > closed_at + timedelta(days=policy["disputes.window_days"]):
            raise BusinessRuleViolation("The dispute window has closed.", code="dispute_window_closed")
        try:
            with transaction.atomic():
                dispute = Dispute.objects.create(
                    ride=ride,
                    opened_by=user,
                    opened_by_role=role,
                    against=against,
                    against_role=against_role,
                    category=category,
                    description=description,
                    is_safety=category == DisputeCategory.SAFETY,
                )
        except IntegrityError:
            raise Conflict("You already have an open dispute for this ride.", code="dispute_open")
        if ride.status != "disputed":
            mark_disputed(ride, user, role)
        if against is not None:
            notify(against, "trust.dispute_opened", {"dispute_id": str(dispute.pk), "ride_id": str(ride.pk)})
        notify_staff(
            "disputes.review",
            "staff.dispute_opened",
            {"dispute_id": str(dispute.pk), "ride_id": str(ride.pk), "is_safety": dispute.is_safety},
        )
    return dispute


def add_dispute_note(dispute, user, role, note):
    if dispute.status not in (DisputeStatus.OPEN, DisputeStatus.UNDER_REVIEW):
        raise Conflict("Dispute is closed.", code="dispute_closed")
    return DisputeNote.objects.create(dispute=dispute, author=user, author_role=role, note=note)


def resolve_dispute(dispute, *, uphold, reviewer, note, violation_kind=None, request=None):
    if not note:
        raise BusinessRuleViolation("A resolution note is required.", code="reason_required")
    with transaction.atomic():
        dispute = Dispute.objects.select_for_update().get(pk=dispute.pk)
        if dispute.status in (DisputeStatus.UPHELD, DisputeStatus.REJECTED):
            raise Conflict(f"Dispute already {dispute.status}.", code="already_decided")
        if reviewer.pk in (dispute.opened_by_id, dispute.against_id):
            raise BusinessRuleViolation("Parties cannot resolve their own dispute.", code="self_review")
        dispute.status = DisputeStatus.UPHELD if uphold else DisputeStatus.REJECTED
        dispute.resolution_note = note
        dispute.resolved_by = reviewer
        dispute.resolved_at = timezone.now()
        dispute.save()
        violation = None
        if uphold and dispute.category == DisputeCategory.NO_SHOW_CONTEST:
            # The contested no-show is overturned; the rider is not penalised.
            for v in Violation.objects.select_for_update().filter(
                ride=dispute.ride, kind=ViolationKind.RIDER_NO_SHOW, subject=dispute.opened_by
            ):
                if v.status in (ViolationStatus.PENDING_REVIEW, ViolationStatus.VERIFIED):
                    v.status = ViolationStatus.OVERTURNED
                    v.reviewed_by, v.reviewed_at, v.review_note = reviewer, timezone.now(), f"dispute upheld: {note}"
                    v.save()
                    EnforcementAction.objects.filter(violation=v).update(status=EnforcementStatus.REVOKED)
            refresh_trust(dispute.opened_by, dispute.opened_by_role)
        elif uphold and dispute.against_id:
            kind = violation_kind or {
                DisputeCategory.FARE: ViolationKind.PRICE_NON_COMPLIANCE,
                DisputeCategory.SAFETY: ViolationKind.SAFETY,
            }.get(dispute.category, ViolationKind.COMPLAINT_UPHELD)
            violation = record_incident(
                dispute.against,
                dispute.against_role,
                kind,
                ride=dispute.ride,
                dispute=dispute,
                reported_by=dispute.opened_by,
                evidence={"dispute_id": str(dispute.pk), "category": dispute.category},
            )
            refresh_trust(dispute.against, dispute.against_role)
        audit.record(
            "trust.dispute_resolved",
            request=request,
            target=dispute,
            data={"upheld": uphold, "violation_id": str(violation.pk) if violation else None},
        )
        for party in filter(None, [dispute.opened_by, dispute.against]):
            notify(party, "trust.dispute_resolved", {"dispute_id": str(dispute.pk), "status": dispute.status})
    return dispute, violation


# ---------------------------------------------------------------- rewards


def reward_eligibility(user, role, policy=None):
    policy = policy or current_policy()
    summary = public_summary(user, role)
    window_start = timezone.now() - timedelta(days=policy["enforcement.window_days"])
    recent = Violation.objects.filter(
        subject=user, subject_role=role, status=ViolationStatus.VERIFIED, reviewed_at__gte=window_start
    ).exists()
    min_tier = policy["rewards.min_tier"]
    tier_ok = TIER_ORDER.index(summary["tier"]) >= TIER_ORDER.index(min_tier) if min_tier in TIER_ORDER else False
    eligible = policy["rewards.renewal_discount_enabled"] and tier_ok and not recent
    return {
        "enabled": policy["rewards.renewal_discount_enabled"],
        "eligible": eligible,
        "tier": summary["tier"],
        "min_tier": min_tier,
        "recent_verified_violations": recent,
        "discount_pct": policy["rewards.renewal_discount_pct"] if eligible else 0,
    }
