"""Ride lifecycle services. Every mutation: row lock on the ride, expected-version check, state-machine
validation, version bump, append-only event, and post-commit notifications (ADR-0004, T6/T7)."""

from datetime import timedelta

from django.db import IntegrityError, transaction
from django.http import Http404
from django.utils import timezone

from apps.core import audit
from apps.core.context import require_tenant
from apps.core.exceptions import BusinessRuleViolation, Conflict, NotEligible, VersionConflict
from apps.drivers import services as driver_services
from apps.geo import services as geo
from apps.notifications.services import notify
from apps.tenancy.policy import current_policy

from . import state_machine as sm
from .models import (
    DRIVER_ACTIVE_STATUSES,
    AmendmentStatus,
    Bid,
    BidStatus,
    DispatchCandidate,
    EvidenceKind,
    LocationEvidence,
    Ride,
    RideAmendment,
    RideEvent,
    RideStatus,
)

# ---------------------------------------------------------------- helpers


def _lock(ride_id):
    ride = Ride.objects.select_for_update().filter(pk=ride_id).first()
    if ride is None:
        raise Http404
    return ride


def _check_version(ride, expected_version):
    if expected_version is not None and expected_version != ride.version:
        raise VersionConflict(detail={"detail": "Ride changed; refresh and retry.", "current_version": ride.version})


def _event(ride, event_type, *, actor=None, role=sm.SYSTEM, from_status="", to_status="", data=None, device_ts=None):
    ride.event_seq += 1
    Ride.objects.filter(pk=ride.pk).update(event_seq=ride.event_seq)
    return RideEvent.objects.create(
        ride=ride,
        seq=ride.event_seq,
        event_type=event_type,
        actor=actor,
        actor_role=role,
        from_status=from_status,
        to_status=to_status,
        data=data or {},
        device_ts=device_ts,
    )


def _transition(ride, action, *, actor=None, role, data=None, device_ts=None, **fields):
    target = sm.target_for(ride.status, action, role)
    previous = ride.status
    ride.status = target
    ride.version += 1
    for name, value in fields.items():
        setattr(ride, name, value)
    ride.save()
    _event(ride, action, actor=actor, role=role, from_status=previous, to_status=target, data=data, device_ts=device_ts)
    return ride


def _hint(user, kind, ride, **extra):
    """Persisted notification + WebSocket hint after commit (never the source of truth)."""
    notify(user, kind, {"ride_id": str(ride.pk), "status": ride.status, "version": ride.version, "seq": ride.event_seq, **extra})


def _driver_busy(driver, exclude_ride_id=None):
    qs = Ride.objects.filter(driver=driver, status__in=DRIVER_ACTIVE_STATUSES)
    if exclude_ride_id:
        qs = qs.exclude(pk=exclude_ride_id)
    return qs.exists()


def _assert_rider(ride, user):
    if ride.rider_id != user.pk:
        raise Http404


def _assert_assigned_driver(ride, driver):
    if ride.driver_id != driver.pk:
        raise Http404


def _expire_open_bids(ride, now=None):
    now = now or timezone.now()
    return Bid.objects.filter(ride=ride, status=BidStatus.OPEN, expires_at__lte=now).update(status=BidStatus.EXPIRED)


# ---------------------------------------------------------------- timeouts (lazy + worker)


def refresh_timeouts(ride_id):
    """Applies elapsed timers (bid expiry, confirmation timeout, unmatched expiry) in their own transaction."""
    now = timezone.now()
    policy = current_policy()
    with transaction.atomic():
        ride = _lock(ride_id)
        _expire_open_bids(ride, now)
        if ride.status == RideStatus.MATCH_PENDING and ride.match_deadline and ride.match_deadline <= now:
            _release_match(ride, action="match_timeout", role=sm.SYSTEM, bid_status=BidStatus.EXPIRED)
        elif ride.status in (RideStatus.REQUESTED, RideStatus.BIDDING) and (
            ride.created_at + timedelta(seconds=policy["rides.bidding_timeout_seconds"]) <= now
        ):
            _close_bids(ride)
            _transition(
                ride,
                "expire",
                role=sm.SYSTEM,
                cancelled_at=now,
                cancel_reason="no_match_timeout",
                cancelled_by_role=sm.SYSTEM,
                cancellation_late=False,
            )
            _hint(ride.rider, "ride.expired", ride)
    return ride


def process_all_timeouts():
    """Worker entry point: scans every active tenant (system context) and applies timers per tenant."""
    from apps.core.context import system_context, tenant_context
    from apps.tenancy.models import Tenant

    processed = 0
    with system_context():
        tenants = list(Tenant.objects.all())
    for tenant in tenants:
        with tenant_context(tenant):
            now = timezone.now()
            policy = current_policy()
            Bid.objects.filter(status=BidStatus.OPEN, expires_at__lte=now).update(status=BidStatus.EXPIRED)
            stale = Ride.objects.filter(status=RideStatus.MATCH_PENDING, match_deadline__lte=now).values_list("id", flat=True)
            old = Ride.objects.filter(
                status__in=[RideStatus.REQUESTED, RideStatus.BIDDING],
                created_at__lte=now - timedelta(seconds=policy["rides.bidding_timeout_seconds"]),
            ).values_list("id", flat=True)
            for ride_id in [*stale, *old]:
                refresh_timeouts(ride_id)
                processed += 1
    return processed


# ---------------------------------------------------------------- request & dispatch


def create_ride(rider, *, pickup, pickup_landmark, dropoff, dropoff_landmark, city_id=None, rider_note="", request=None):
    from apps.trust.services import active_restriction

    tenant = require_tenant()
    policy = current_policy()
    if not tenant.is_active and policy["tenant.block_new_rides_when_suspended"]:
        raise NotEligible("This operator is not accepting new ride requests.", code="tenant_suspended")
    restriction = active_restriction(rider, "rider")
    if restriction is not None:
        raise NotEligible(f"Ride requests are restricted until {restriction.ends_at.isoformat()}.", code="restricted")
    city = geo.resolve_city(pickup, city_id)
    estimate = geo.fare_estimate(pickup, dropoff, policy)
    try:
        with transaction.atomic():
            ride = Ride.objects.create(
                rider=rider,
                city=city,
                pickup=pickup,
                pickup_landmark=pickup_landmark,
                dropoff=dropoff,
                dropoff_landmark=dropoff_landmark,
                rider_note=rider_note,
                currency=tenant.currency,
                estimate_min_minor=estimate["min_minor"],
                estimate_max_minor=estimate["max_minor"],
                estimated_distance_m=estimate["distance_m"],
                config_version=policy.version,
            )
    except IntegrityError:
        raise Conflict("You already have an active ride.", code="active_ride_exists")
    _event(
        ride,
        "requested",
        actor=rider,
        role=sm.RIDER,
        to_status=ride.status,
        data={"estimate": [estimate["min_minor"], estimate["max_minor"]], "config_version": policy.version},
    )
    _dispatch_wave(ride, policy, actor=rider)
    audit.record("ride.requested", request=request, target=ride)
    return ride


def _eligible_for_dispatch(driver, policy):
    return driver_services.eligibility(driver, policy)["eligible"] and not _driver_busy(driver)


def _dispatch_wave(ride, policy, actor=None):
    wave = ride.wave_count + 1
    if wave > policy["dispatch.max_waves"]:
        raise BusinessRuleViolation("Maximum dispatch waves reached; cancel and request again later.", code="max_waves_reached")
    radius = policy["dispatch.initial_radius_m"] + policy["dispatch.radius_step_m"] * (wave - 1)
    already = set(DispatchCandidate.objects.filter(ride=ride).values_list("driver_id", flat=True))
    selected = []
    for location in geo.nearby_driver_locations(
        ride.pickup, radius, policy, exclude_driver_ids=already, limit=policy["dispatch.wave_size"] * 4
    ):
        driver = location.driver
        if driver.user_id == ride.rider_id or not _eligible_for_dispatch(driver, policy):
            continue
        selected.append((driver, int(location.distance.m)))
        if len(selected) >= policy["dispatch.wave_size"]:
            break
    for driver, distance in selected:
        DispatchCandidate.objects.create(ride=ride, driver=driver, wave=wave, distance_m=distance)
    ride.wave_count = wave
    ride.dispatch_radius_m = radius
    ride.save(update_fields=["wave_count", "dispatch_radius_m", "updated_at"])
    _event(ride, "wave_dispatched", data={"wave": wave, "radius_m": radius, "drivers": len(selected)})
    if selected and ride.status == RideStatus.REQUESTED:
        _transition(ride, "dispatch", role=sm.SYSTEM, bidding_at=timezone.now())
    for driver, _distance in selected:
        _hint(driver.user, "ride.offer", ride, landmark=ride.pickup_landmark)
    _hint(ride.rider, "ride.dispatched", ride, wave=wave, drivers=len(selected))
    return len(selected)


def dispatch_next_wave(ride_id, rider, expected_version=None):
    refresh_timeouts(ride_id)
    policy = current_policy()
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_rider(ride, rider)
        _check_version(ride, expected_version)
        if ride.status not in (RideStatus.REQUESTED, RideStatus.BIDDING):
            raise Conflict(f"Cannot dispatch while {ride.status}.", code="invalid_transition")
        count = _dispatch_wave(ride, policy, actor=rider)
    return ride, count


# ---------------------------------------------------------------- bids


def offers_for_driver(driver):
    return (
        Ride.objects.filter(candidates__driver=driver, status=RideStatus.BIDDING)
        .exclude(rider=driver.user)
        .distinct()
        .order_by("-created_at")
    )


def place_bid(ride_id, driver, *, amount_minor, eta_seconds, request=None):
    policy = current_policy()
    driver_services.assert_eligible(driver, policy)
    if not driver.is_online:
        raise NotEligible("Go online before bidding.", code="driver_offline")
    refresh_timeouts(ride_id)
    with transaction.atomic():
        ride = _lock(ride_id)
        if not DispatchCandidate.objects.filter(ride=ride, driver=driver).exists():
            raise Http404  # drivers only see/bid on requests dispatched to them
        if ride.status != RideStatus.BIDDING:
            raise Conflict(f"Bidding is closed ({ride.status}).", code="bidding_closed")
        if _driver_busy(driver):
            raise Conflict("You already have an active ride.", code="driver_busy")
        if amount_minor <= 0:
            raise BusinessRuleViolation("Amount must be positive.", code="amount_invalid")
        driver_bids = Bid.objects.filter(ride=ride, driver=driver)
        if driver_bids.count() >= policy["bids.max_per_driver_per_ride"]:
            raise BusinessRuleViolation("Bid limit for this request reached.", code="bid_limit")
        open_elsewhere = Bid.objects.filter(driver=driver, status=BidStatus.OPEN, expires_at__gt=timezone.now()).exclude(ride=ride)
        if open_elsewhere.count() >= policy["bids.max_open_per_driver"]:
            raise BusinessRuleViolation("Too many open bids.", code="open_bid_limit")
        driver_bids.filter(status=BidStatus.OPEN).update(status=BidStatus.WITHDRAWN)
        bid = Bid.objects.create(
            ride=ride,
            driver=driver,
            amount_minor=amount_minor,
            currency=ride.currency,
            eta_seconds=eta_seconds,
            expires_at=timezone.now() + timedelta(seconds=policy["bids.expiry_seconds"]),
        )
        _event(
            ride,
            "bid_created",
            actor=driver.user,
            role=sm.DRIVER,
            data={"bid_id": str(bid.pk), "amount_minor": amount_minor, "eta_seconds": eta_seconds},
        )
        _hint(ride.rider, "ride.bid_created", ride, bid_id=str(bid.pk))
    return bid


def withdraw_bid(ride_id, bid_id, driver):
    with transaction.atomic():
        ride = _lock(ride_id)
        bid = Bid.objects.select_for_update().filter(pk=bid_id, ride=ride, driver=driver).first()
        if bid is None:
            raise Http404
        if bid.status != BidStatus.OPEN:
            raise Conflict(f"Bid is {bid.status}.", code="bid_not_open")
        bid.status = BidStatus.WITHDRAWN
        bid.save(update_fields=["status", "updated_at"])
        _event(ride, "bid_withdrawn", actor=driver.user, role=sm.DRIVER, data={"bid_id": str(bid.pk)})
        _hint(ride.rider, "ride.bid_withdrawn", ride, bid_id=str(bid.pk))
    return bid


def open_bids(ride):
    return Bid.objects.filter(ride=ride, status=BidStatus.OPEN, expires_at__gt=timezone.now()).select_related("driver__user")


# ---------------------------------------------------------------- match


def select_bid(ride_id, rider, bid_id, expected_version, request=None):
    refresh_timeouts(ride_id)
    policy = current_policy()
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_rider(ride, rider)
        _check_version(ride, expected_version)
        bid = Bid.objects.select_for_update().filter(pk=bid_id, ride=ride).first()
        if bid is None:
            raise Http404
        sm.target_for(ride.status, "select", sm.RIDER)
        now = timezone.now()
        if bid.status != BidStatus.OPEN:
            raise Conflict(f"Bid is {bid.status}.", code="bid_not_open")
        if bid.expires_at <= now:
            Bid.objects.filter(pk=bid.pk).update(status=BidStatus.EXPIRED)
            raise Conflict("Bid expired before selection.", code="bid_expired")
        try:
            with transaction.atomic():
                bid.status = BidStatus.SELECTED
                bid.save(update_fields=["status", "updated_at"])
                _transition(
                    ride,
                    "select",
                    actor=rider,
                    role=sm.RIDER,
                    data={"bid_id": str(bid.pk)},
                    driver=bid.driver,
                    selected_bid=bid,
                    selected_at=now,
                    match_deadline=now + timedelta(seconds=policy["match.driver_confirm_timeout_seconds"]),
                )
        except IntegrityError:
            # Partial unique index: the driver was matched elsewhere a moment ago (two riders, one driver).
            raise Conflict("This driver is no longer available; choose another offer.", code="driver_unavailable")
        _hint(bid.driver.user, "ride.selected", ride, bid_id=str(bid.pk), confirm_by=ride.match_deadline.isoformat())
        audit.record("ride.bid_selected", request=request, target=ride, data={"bid_id": str(bid.pk)})
    return ride


def _release_match(ride, *, action, role, bid_status, actor=None, reason=""):
    bid = ride.selected_bid
    driver = ride.driver
    if bid is not None:
        Bid.objects.filter(pk=bid.pk).update(status=bid_status)
    _transition(
        ride,
        action,
        actor=actor,
        role=role,
        data={"bid_id": str(bid.pk) if bid else None, "reason": reason},
        driver=None,
        selected_bid=None,
        match_deadline=None,
        selected_at=None,
    )
    _hint(ride.rider, "ride.match_released", ride, reason=action)
    if driver is not None and role == sm.SYSTEM:
        _hint(driver.user, "ride.match_expired", ride)


def confirm_match(ride_id, driver, expected_version, request=None):
    refresh_timeouts(ride_id)
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        _check_version(ride, expected_version)
        sm.target_for(ride.status, "confirm", sm.DRIVER)
        driver_services.assert_eligible(driver)  # e.g. documents expired mid-shift
        now = timezone.now()
        bid = Bid.objects.select_for_update().get(pk=ride.selected_bid_id)
        bid.status = BidStatus.ACCEPTED
        bid.save(update_fields=["status", "updated_at"])
        losers = list(Bid.objects.filter(ride=ride, status=BidStatus.OPEN).select_related("driver__user"))
        Bid.objects.filter(ride=ride, status=BidStatus.OPEN).update(status=BidStatus.LOST)
        _transition(
            ride,
            "confirm",
            actor=driver.user,
            role=sm.DRIVER,
            data={"agreed_fare_minor": bid.amount_minor},
            agreed_fare_minor=bid.amount_minor,
            price_locked_at=now,
            assigned_at=now,
            match_deadline=None,
        )
        _hint(ride.rider, "ride.assigned", ride)
        for lost in losers:
            _hint(lost.driver.user, "ride.bid_lost", ride, bid_id=str(lost.pk))
        audit.record("ride.match_confirmed", request=request, target=ride, data={"fare": bid.amount_minor})
    return ride


def decline_match(ride_id, driver, expected_version, reason=""):
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        _check_version(ride, expected_version)
        sm.target_for(ride.status, "decline", sm.DRIVER)
        # Declining before confirmation is never penalised (R02-06).
        _release_match(ride, action="decline", role=sm.DRIVER, bid_status=BidStatus.DECLINED, actor=driver.user, reason=reason)
    return ride


# ---------------------------------------------------------------- trip


def _driver_action(ride_id, driver, expected_version, action, *, device_ts=None, data=None, **fields):
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        _check_version(ride, expected_version)
        _transition(ride, action, actor=driver.user, role=sm.DRIVER, device_ts=device_ts, data=data, **fields)
        return ride


def mark_en_route(ride_id, driver, expected_version):
    ride = _driver_action(ride_id, driver, expected_version, "en_route", en_route_at=timezone.now())
    _hint(ride.rider, "ride.en_route", ride)
    return ride


def mark_arrived(ride_id, driver, expected_version, *, point, accuracy_m, device_ts=None):
    """Arrival is recorded with geofence evaluation; GPS is evidence, never sole proof (T3)."""
    policy = current_policy()
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        _check_version(ride, expected_version)
        distance = geo.haversine_m(point, ride.pickup)
        usable = accuracy_m <= policy["noshow.max_accuracy_m"]
        within = usable and distance <= policy["noshow.geofence_m"] + accuracy_m
        _transition(
            ride,
            "arrive",
            actor=driver.user,
            role=sm.DRIVER,
            device_ts=device_ts,
            data={"distance_m": int(distance), "accuracy_m": accuracy_m, "within_geofence": within},
            arrived_at=timezone.now(),
            arrival_distance_m=int(distance),
            arrival_accuracy_m=accuracy_m,
            arrival_within_geofence=within,
        )
        LocationEvidence.objects.create(
            ride=ride, actor=driver.user, kind=EvidenceKind.ARRIVAL, point=point, accuracy_m=accuracy_m, device_ts=device_ts
        )
        _hint(ride.rider, "ride.driver_arrived", ride)
    return ride


def record_contact_attempt(ride_id, driver, method):
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        if ride.status not in (RideStatus.EN_ROUTE, RideStatus.ARRIVED):
            raise Conflict("Contact attempts are recorded while en route or arrived.", code="invalid_transition")
        event = _event(ride, "contact_attempt", actor=driver.user, role=sm.DRIVER, data={"method": method})
        # The platform also notifies the rider; the notification itself is part of the evidence.
        _hint(ride.rider, "ride.driver_waiting", ride, attempt_seq=event.seq)
    return event


def start_trip(ride_id, driver, expected_version):
    ride = _driver_action(ride_id, driver, expected_version, "start", started_at=timezone.now())
    _hint(ride.rider, "ride.started", ride)
    return ride


def complete_trip(ride_id, driver, expected_version):
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        _check_version(ride, expected_version)
        _transition(
            ride,
            "complete",
            actor=driver.user,
            role=sm.DRIVER,
            data={"cash_due_minor": ride.agreed_fare_minor},
            completed_at=timezone.now(),
            cash_amount_minor=ride.agreed_fare_minor,
        )
        _hint(ride.rider, "ride.completed", ride, cash_due_minor=ride.agreed_fare_minor)
        from apps.trust.services import refresh_trust

        refresh_trust(ride.rider, "rider")
        refresh_trust(driver.user, "driver")
    return ride


def mark_no_show(ride_id, driver, expected_version, request=None):
    """Rider no-show only with wait time + geofence-valid arrival + contact attempt (BUSINESS_RULES §3).
    The resulting violation is pending human review and appealable; nothing is applied automatically."""
    policy = current_policy()
    with transaction.atomic():
        ride = _lock(ride_id)
        _assert_assigned_driver(ride, driver)
        _check_version(ride, expected_version)
        sm.target_for(ride.status, "no_show", sm.DRIVER)
        now = timezone.now()
        waited = int((now - ride.arrived_at).total_seconds()) if ride.arrived_at else 0
        attempts = RideEvent.objects.filter(ride=ride, event_type="contact_attempt", created_at__gte=ride.arrived_at).count()
        failures = []
        if waited < policy["noshow.min_wait_seconds"]:
            failures.append(f"wait_too_short:{waited}s<{policy['noshow.min_wait_seconds']}s")
        if not ride.arrival_within_geofence:
            failures.append("arrival_not_within_geofence")
        if policy["noshow.require_contact_attempt"] and attempts < 1:
            failures.append("no_contact_attempt")
        if failures:
            raise BusinessRuleViolation(
                {"detail": "No-show evidence is insufficient.", "failed_checks": failures}, code="no_show_evidence_insufficient"
            )
        evidence = {
            "waited_seconds": waited,
            "contact_attempts": attempts,
            "arrival_distance_m": ride.arrival_distance_m,
            "arrival_accuracy_m": ride.arrival_accuracy_m,
            "geofence_m": policy["noshow.geofence_m"],
            "config_version": policy.version,
        }
        _transition(ride, "no_show", actor=driver.user, role=sm.DRIVER, data=evidence, no_show_evidence=evidence)
        from apps.trust.services import record_incident

        record_incident(ride.rider, "rider", "rider_no_show", ride=ride, evidence=evidence, reported_by=driver.user)
        _hint(ride.rider, "ride.no_show_recorded", ride)
        audit.record("ride.no_show", request=request, target=ride, data=evidence)
    return ride


def cancel_ride(ride_id, user, role, expected_version, reason="", request=None):
    policy = current_policy()
    with transaction.atomic():
        ride = _lock(ride_id)
        if role == sm.RIDER:
            _assert_rider(ride, user)
        else:
            _assert_assigned_driver(ride, driver_services.get_driver_for_user(user))
        _check_version(ride, expected_version)
        action = "rider_cancel" if role == sm.RIDER else "driver_cancel"
        sm.target_for(ride.status, action, role)
        now = timezone.now()
        late = False
        if ride.assigned_at is not None:
            late = now > ride.assigned_at + timedelta(seconds=policy["cancellation.free_after_match_seconds"])
        previous_status = ride.status
        driver = ride.driver
        _close_bids(ride)
        _transition(
            ride,
            action,
            actor=user,
            role=role,
            data={"reason": reason, "late": late},
            cancelled_at=now,
            cancelled_by=user,
            cancelled_by_role=role,
            cancel_reason=reason,
            cancellation_late=late,
        )
        if late:
            from apps.trust.services import record_incident

            kind = "rider_late_cancellation" if role == sm.RIDER else "driver_late_cancellation"
            subject = ride.rider if role == sm.RIDER else user
            record_incident(
                subject,
                role,
                kind,
                ride=ride,
                reported_by=None,
                evidence={
                    "previous_status": previous_status,
                    "assigned_at": ride.assigned_at.isoformat(),
                    "cancelled_at": now.isoformat(),
                    "reason": reason,
                },
            )
        if role == sm.RIDER and driver is not None:
            _hint(driver.user, "ride.cancelled", ride, by="rider")
        if role == sm.DRIVER:
            _hint(ride.rider, "ride.cancelled", ride, by="driver")
        audit.record("ride.cancelled", request=request, target=ride, data={"by": role, "late": late})
    return ride


def _close_bids(ride):
    Bid.objects.filter(ride=ride, status__in=[BidStatus.OPEN, BidStatus.SELECTED]).update(status=BidStatus.LOST)


def confirm_cash(ride_id, user, role):
    """Cash is paid rider -> driver directly; the platform records declarations only (D002)."""
    with transaction.atomic():
        ride = _lock(ride_id)
        if role == sm.RIDER:
            _assert_rider(ride, user)
            field = "cash_rider_confirmed_at"
        else:
            _assert_assigned_driver(ride, driver_services.get_driver_for_user(user))
            field = "cash_driver_confirmed_at"
        if ride.status not in (RideStatus.COMPLETED, RideStatus.DISPUTED) or ride.completed_at is None:
            raise Conflict("Cash can be confirmed after completion only.", code="invalid_transition")
        if getattr(ride, field) is None:
            setattr(ride, field, timezone.now())
            ride.version += 1
            ride.save(update_fields=[field, "version", "updated_at"])
            _event(ride, "cash_confirmed", actor=user, role=role, data={"amount_minor": ride.cash_amount_minor})
            other = ride.driver.user if role == sm.RIDER else ride.rider
            _hint(other, "ride.cash_confirmed", ride, by=role)
    return ride


# ---------------------------------------------------------------- amendments


AMENDABLE = (RideStatus.ASSIGNED, RideStatus.EN_ROUTE, RideStatus.ARRIVED, RideStatus.IN_PROGRESS)


def _participant_role(ride, user):
    if ride.rider_id == user.pk:
        return sm.RIDER
    if ride.driver_id and ride.driver.user_id == user.pk:
        return sm.DRIVER
    raise Http404


def propose_amendment(ride_id, user, *, new_fare_minor, reason, new_dropoff=None, new_dropoff_landmark=""):
    with transaction.atomic():
        ride = _lock(ride_id)
        role = _participant_role(ride, user)
        if ride.status not in AMENDABLE:
            raise Conflict("Amendments are possible only during an assigned trip.", code="invalid_transition")
        try:
            with transaction.atomic():
                amendment = RideAmendment.objects.create(
                    ride=ride,
                    proposed_by=user,
                    proposed_by_role=role,
                    new_fare_minor=new_fare_minor,
                    new_dropoff=new_dropoff,
                    new_dropoff_landmark=new_dropoff_landmark,
                    reason=reason,
                )
        except IntegrityError:
            raise Conflict("Another amendment is pending.", code="amendment_pending")
        _event(
            ride,
            "amendment_proposed",
            actor=user,
            role=role,
            data={"amendment_id": str(amendment.pk), "new_fare_minor": new_fare_minor},
        )
        other = ride.driver.user if role == sm.RIDER else ride.rider
        _hint(other, "ride.amendment_proposed", ride, amendment_id=str(amendment.pk))
    return amendment


def respond_amendment(ride_id, amendment_id, user, accept):
    with transaction.atomic():
        ride = _lock(ride_id)
        role = _participant_role(ride, user)
        amendment = RideAmendment.objects.select_for_update().filter(pk=amendment_id, ride=ride).first()
        if amendment is None:
            raise Http404
        if amendment.status != AmendmentStatus.PENDING:
            raise Conflict(f"Amendment is {amendment.status}.", code="amendment_decided")
        if amendment.proposed_by_id == user.pk:
            raise BusinessRuleViolation("The other party must respond.", code="self_response")
        if accept and ride.status not in AMENDABLE:
            raise Conflict("Ride is no longer amendable.", code="invalid_transition")
        amendment.status = AmendmentStatus.ACCEPTED if accept else AmendmentStatus.REJECTED
        amendment.responded_by = user
        amendment.responded_at = timezone.now()
        amendment.save(update_fields=["status", "responded_by", "responded_at", "updated_at"])
        if accept:
            ride.agreed_fare_minor = amendment.new_fare_minor
            if amendment.new_dropoff is not None:
                ride.dropoff = amendment.new_dropoff
                ride.dropoff_landmark = amendment.new_dropoff_landmark or ride.dropoff_landmark
            ride.version += 1
            ride.save()
        _event(
            ride,
            "amendment_accepted" if accept else "amendment_rejected",
            actor=user,
            role=role,
            data={"amendment_id": str(amendment.pk), "new_fare_minor": amendment.new_fare_minor},
        )
        _hint(amendment.proposed_by, "ride.amendment_" + amendment.status, ride, amendment_id=str(amendment.pk))
    return amendment


# ---------------------------------------------------------------- location evidence


def record_driver_location_evidence(driver, location):
    policy = current_policy()
    ride = Ride.objects.filter(driver=driver, status__in=[RideStatus.EN_ROUTE, RideStatus.ARRIVED, RideStatus.IN_PROGRESS]).first()
    if ride is None:
        return None
    last = LocationEvidence.objects.filter(ride=ride, kind=EvidenceKind.PING).order_by("-created_at").first()
    if last and (timezone.now() - last.created_at).total_seconds() < policy["rides.evidence_ping_interval_seconds"]:
        return None
    return LocationEvidence.objects.create(
        ride=ride,
        actor=driver.user,
        kind=EvidenceKind.PING,
        point=location.point,
        accuracy_m=location.accuracy_m,
        device_ts=location.device_ts,
    )


def mark_disputed(ride, user, role):
    """Called by the trust app inside its transaction when a dispute is opened."""
    previous = ride.status
    _transition(ride, "dispute", actor=user, role=role, status_before_dispute=previous)
    return ride
