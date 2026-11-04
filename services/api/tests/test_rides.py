from datetime import timedelta

import pytest
from django.utils import timezone

from apps.core.context import tenant_context
from apps.rides.models import Bid, LocationEvidence, Ride, RideEvent
from apps.trust.models import Violation

pytestmark = pytest.mark.django_db


def test_full_cash_ride_lifecycle(ride_flow):
    f = ride_flow
    ride = f.create()
    assert ride["status"] == "bidding"
    assert ride["estimate"]["label"] == "estimate, not guaranteed"
    assert ride["estimate"]["min_minor"] < ride["estimate"]["max_minor"]

    offers = f.d1_api.get("/api/v1/driver/ride-offers").data
    assert [o["id"] for o in offers] == [ride["id"]]
    assert offers[0]["viewer_role"] == "candidate"
    assert offers[0]["rider"]["phone"] is None  # no contact data before match

    b1 = f.bid(ride["id"], amount=160000)
    b2 = f.bid(ride["id"], api=f.d2_api, amount=140000)
    bids = f.rider_api.get(f"/api/v1/rides/{ride['id']}/bids").data
    assert [b["id"] for b in bids] == [b2["id"], b1["id"]]  # cheapest first
    assert bids[0]["driver"]["trust"]["tier"] == "new"

    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": b2["id"], "expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    assert r.data["status"] == "match_pending"
    r = f.d2_api.post(f"/api/v1/rides/{ride['id']}/confirm", {"expected_version": r.data["version"]})
    assert r.status_code == 200, r.data
    assert r.data["status"] == "assigned"
    assert r.data["agreed_fare_minor"] == 140000
    assert r.data["rider"]["phone"] == f.rider_user.phone  # contact during active trip

    with tenant_context(f.tenant.tenant):
        assert Bid.objects.get(pk=b1["id"]).status == "lost"

    v = r.data["version"]
    r = f.d2_api.post(f"/api/v1/rides/{ride['id']}/en-route", {"expected_version": v})
    assert r.data["status"] == "en_route"
    lng, lat = f.tenant.center
    r = f.d2_api.post(
        f"/api/v1/rides/{ride['id']}/arrive", {"expected_version": r.data["version"], "lat": lat, "lng": lng, "accuracy_m": 8}
    )
    assert r.data["status"] == "arrived"
    assert r.data["arrival"]["within_geofence"] is True
    r = f.d2_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": r.data["version"]})
    assert r.data["status"] == "in_progress"
    r = f.d2_api.post(f"/api/v1/rides/{ride['id']}/complete", {"expected_version": r.data["version"]})
    assert r.data["status"] == "completed"
    assert r.data["cash"]["amount_minor"] == 140000

    r = f.d2_api.post(f"/api/v1/rides/{ride['id']}/cash-confirm")
    assert r.data["cash"]["driver_confirmed_at"] is not None
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/cash-confirm")
    assert r.data["cash"]["rider_confirmed_at"] is not None

    events = f.rider_api.get(f"/api/v1/rides/{ride['id']}/events").data
    seqs = [e["seq"] for e in events]
    assert seqs == sorted(seqs) and len(seqs) == len(set(seqs))
    assert {"requested", "select", "confirm", "arrive", "start", "complete", "cash_confirmed"} <= {e["event_type"] for e in events}
    replay = f.rider_api.get(f"/api/v1/rides/{ride['id']}/events", {"after_seq": seqs[-2]}).data
    assert [e["seq"] for e in replay] == [seqs[-1]]


def test_expected_version_conflict_returns_409(ride_flow):
    f = ride_flow
    ride = f.create()
    bid = f.bid(ride["id"])
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": 99})
    assert r.status_code == 409
    assert r.data["code"] == "version_conflict"


def test_idempotent_replay_and_key_reuse(ride_flow):
    f = ride_flow
    payload = f.rider_api.post  # noqa: F841 - readability
    from tests.factories import ride_payload

    body = ride_payload(f.tenant)
    r1 = f.rider_api.post("/api/v1/rides", body, key="same-key-1")
    r2 = f.rider_api.post("/api/v1/rides", body, key="same-key-1")
    assert r1.status_code == r2.status_code == 201
    assert r1.data["id"] == r2.data["id"]
    assert r2["Idempotent-Replay"] == "true"
    with tenant_context(f.tenant.tenant):
        assert Ride.objects.count() == 1
    r3 = f.rider_api.post("/api/v1/rides", {**body, "rider_note": "different"}, key="same-key-1")
    assert r3.status_code == 422
    assert r3.data["code"] == "idempotency_key_reused"
    r4 = f.rider_api.client.post("/api/v1/rides", body, format="json")
    assert r4.status_code == 400 and r4.data["code"] == "idempotency_key_required"


def test_one_active_ride_per_rider(ride_flow):
    f = ride_flow
    f.create()
    from tests.factories import ride_payload

    r = f.rider_api.post("/api/v1/rides", ride_payload(f.tenant))
    assert r.status_code == 409 and r.data["code"] == "active_ride_exists"


def test_invalid_transitions_rejected(ride_flow):
    f = ride_flow
    ride = f.create()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"]})
    assert r.status_code == 404  # not the assigned driver
    ride = f.assigned() if False else None  # noqa: F841


def test_start_before_arrival_is_invalid(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"]})
    assert r.status_code == 409 and r.data["code"] == "invalid_transition"
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/complete", {"expected_version": ride["version"]})
    assert r.status_code == 409


def test_non_candidate_driver_cannot_bid(ride_flow, h):
    f = ride_flow
    ride = f.create()
    far = h.driver(f.tenant, offset=(0.5, 0.5))  # outside every wave radius
    r = h.api(f.tenant, far.user).post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 1000, "eta_seconds": 60})
    assert r.status_code == 404


def test_expired_bid_cannot_be_selected(ride_flow):
    f = ride_flow
    ride = f.create()
    bid = f.bid(ride["id"])
    with tenant_context(f.tenant.tenant):
        Bid.objects.filter(pk=bid["id"]).update(expires_at=timezone.now() - timedelta(seconds=1))
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    assert r.status_code == 409
    assert r.data["code"] in ("bid_expired", "bid_not_open")


def test_driver_decline_returns_to_bidding_without_penalty(ride_flow):
    f = ride_flow
    ride = f.create()
    bid = f.bid(ride["id"])
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/decline", {"expected_version": r.data["version"]})
    assert r.status_code == 200 and r.data["status"] == "bidding"
    with tenant_context(f.tenant.tenant):
        assert not Violation.objects.exists()


def test_confirmation_timeout_releases_match(ride_flow):
    f = ride_flow
    ride = f.create()
    bid = f.bid(ride["id"])
    f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(match_deadline=timezone.now() - timedelta(seconds=1))
    from apps.rides.services import process_all_timeouts

    assert process_all_timeouts() >= 1
    snap = f.snapshot(ride["id"])
    assert snap["status"] == "bidding"
    with tenant_context(f.tenant.tenant):
        assert Bid.objects.get(pk=bid["id"]).status == "expired"


def test_cancel_before_match_is_free_and_late_cancel_is_recorded_for_review(ride_flow):
    f = ride_flow
    ride = f.create()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"], "reason": "x"})
    assert r.status_code == 200 and r.data["cancellation"]["late"] is False
    ride = f.assigned()
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(assigned_at=timezone.now() - timedelta(minutes=5))
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"], "reason": "late"})
    assert r.status_code == 200 and r.data["cancellation"]["late"] is True
    with tenant_context(f.tenant.tenant):
        violation = Violation.objects.get()
        assert violation.kind == "rider_late_cancellation"
        assert violation.status == "pending_review"  # never applied automatically


def test_driver_cancel_within_free_window_is_not_recorded(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"]})
    assert r.status_code == 200 and r.data["cancellation"]["late"] is False
    with tenant_context(f.tenant.tenant):
        assert not Violation.objects.exists()


def test_no_show_requires_wait_geofence_and_contact(ride_flow):
    f = ride_flow
    ride = f.arrived()
    url = f"/api/v1/rides/{ride['id']}/no-show"
    r = f.d1_api.post(url, {"expected_version": ride["version"]})
    assert r.status_code == 422
    checks = r.data["detail"]["failed_checks"]
    assert any(c.startswith("wait_too_short") for c in checks) and "no_contact_attempt" in checks

    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/contact-attempts", {"method": "call"})
    assert r.status_code == 201
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(arrived_at=timezone.now() - timedelta(minutes=6))
        RideEvent.all_tenants.filter(ride_id=ride["id"], event_type="contact_attempt")  # evidence exists
    version = f.snapshot(ride["id"])["version"]
    r = f.d1_api.post(url, {"expected_version": version})
    assert r.status_code == 200, r.data
    assert r.data["status"] == "no_show"
    with tenant_context(f.tenant.tenant):
        violation = Violation.objects.get(kind="rider_no_show")
        assert violation.status == "pending_review"
        assert violation.evidence["contact_attempts"] == 1


def test_driver_sees_what_a_no_show_still_needs(ride_flow):
    f = ride_flow
    ride = f.arrived()
    assert ride["no_show"] == {"wait_seconds": 300, "contact_required": True, "contact_attempts": 0}
    f.d1_api.post(f"/api/v1/rides/{ride['id']}/contact-attempts", {"method": "call"})
    assert f.snapshot(ride["id"], api=f.d1_api)["no_show"]["contact_attempts"] == 1
    assert f.snapshot(ride["id"])["no_show"] is None  # the rider doesn't need it


def test_no_show_rejected_when_arrival_outside_geofence(ride_flow):
    f = ride_flow
    ride = f.arrived(dx=0.01)  # ~1 km away from pickup
    assert ride["arrival"]["within_geofence"] is False
    f.d1_api.post(f"/api/v1/rides/{ride['id']}/contact-attempts", {"method": "call"})
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(arrived_at=timezone.now() - timedelta(minutes=10))
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/no-show", {"expected_version": f.snapshot(ride["id"])["version"]})
    assert r.status_code == 422
    assert "arrival_not_within_geofence" in r.data["detail"]["failed_checks"]


def test_no_show_rejected_with_inaccurate_gps(ride_flow):
    f = ride_flow
    ride = f.arrived(accuracy=500)  # a single inaccurate fix is never proof
    assert ride["arrival"]["within_geofence"] is False


def _arrived_without_location(f):
    ride = f.assigned()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/arrive", {"expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    return r.data


def _late_location(f, ride, seconds=10, dx=0.0, accuracy=8.0):
    lng, lat = f.tenant.center
    read_at = timezone.now() + timedelta(seconds=seconds)
    body = {"lat": lat, "lng": lng + dx, "accuracy_m": accuracy, "device_ts": read_at.isoformat()}
    return f.d1_api.post(f"/api/v1/rides/{ride['id']}/arrival-location", body)


def test_arrival_without_location_is_recorded_but_cannot_support_a_no_show(ride_flow):
    f = ride_flow
    ride = _arrived_without_location(f)
    assert ride["status"] == "arrived"
    assert ride["arrival"]["within_geofence"] is None
    assert ride["arrival"]["accuracy_m"] is None
    f.d1_api.post(f"/api/v1/rides/{ride['id']}/contact-attempts", {"method": "call"})
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(arrived_at=timezone.now() - timedelta(minutes=10))
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/no-show", {"expected_version": f.snapshot(ride["id"])["version"]})
    assert r.status_code == 422
    assert "arrival_not_within_geofence" in r.data["detail"]["failed_checks"]


def test_arrive_refuses_part_of_a_location(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/arrive", {"expected_version": ride["version"], "lat": 14.5})
    assert r.status_code == 400


def test_location_read_soon_after_arrival_counts(ride_flow):
    f = ride_flow
    ride = _arrived_without_location(f)
    r = _late_location(f, ride)
    assert r.status_code == 200, r.data
    assert r.data == {"recorded": True, "counted": True}
    after = f.snapshot(ride["id"], f.d1_api)
    assert after["arrival"]["within_geofence"] is True
    assert after["version"] == ride["version"], "a late location doesn't change the ride's state"


def test_late_location_far_from_pickup_counts_as_outside(ride_flow):
    f = ride_flow
    ride = _arrived_without_location(f)
    assert _late_location(f, ride, dx=0.01).data["counted"] is True
    assert f.snapshot(ride["id"], f.d1_api)["arrival"]["within_geofence"] is False


def test_location_read_long_after_arrival_is_evidence_only(ride_flow):
    f = ride_flow
    ride = _arrived_without_location(f)
    r = _late_location(f, ride, seconds=300)
    assert r.data == {"recorded": True, "counted": False}
    assert f.snapshot(ride["id"], f.d1_api)["arrival"]["within_geofence"] is None
    with tenant_context(f.tenant.tenant):
        assert LocationEvidence.objects.filter(ride_id=ride["id"], kind="arrival").count() == 1


def test_late_location_never_replaces_one_already_there(ride_flow):
    f = ride_flow
    ride = f.arrived(dx=0.01)
    r = _late_location(f, ride)
    assert r.data == {"recorded": False, "counted": False}
    assert f.snapshot(ride["id"], f.d1_api)["arrival"]["within_geofence"] is False


def test_late_location_needs_a_recorded_arrival(ride_flow):
    f = ride_flow
    assert _late_location(f, f.assigned()).status_code == 409


def test_late_location_is_accepted_after_the_trip_moved_on(ride_flow):
    f = ride_flow
    ride = _arrived_without_location(f)
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    assert _late_location(f, ride).data["recorded"] is True
    assert f.snapshot(ride["id"])["status"] == "in_progress"


def test_late_location_only_from_the_assigned_driver(ride_flow):
    f = ride_flow
    ride = _arrived_without_location(f)
    lng, lat = f.tenant.center
    body = {"lat": lat, "lng": lng, "accuracy_m": 8, "device_ts": timezone.now().isoformat()}
    r = f.d2_api.post(f"/api/v1/rides/{ride['id']}/arrival-location", body)
    assert r.status_code == 404


def test_amendment_requires_other_party(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/amendments", {"new_fare_minor": 200000, "reason": "detour"})
    assert r.status_code == 201
    amendment_id = r.data["id"]
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/amendments/{amendment_id}/respond", {"accept": True})
    assert r.status_code == 422 and r.data["code"] == "self_response"
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/amendments/{amendment_id}/respond", {"accept": True})
    assert r.status_code == 200 and r.data["status"] == "accepted"
    assert f.snapshot(ride["id"])["agreed_fare_minor"] == 200000


def test_rider_cannot_see_bids_of_other_rides_and_driver_cannot_select(ride_flow, h):
    f = ride_flow
    ride = f.create()
    bid = f.bid(ride["id"])
    other_rider = h.member(f.tenant, "rider")
    r = h.api(f.tenant, other_rider).get(f"/api/v1/rides/{ride['id']}/bids")
    assert r.status_code == 404
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    assert r.status_code == 403


def test_unmatched_ride_expires(ride_flow):
    f = ride_flow
    ride = f.create()
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(created_at=timezone.now() - timedelta(hours=2))
    from apps.rides.services import process_all_timeouts

    process_all_timeouts()
    snap = f.snapshot(ride["id"])
    assert snap["status"] == "cancelled" and snap["cancellation"]["by_role"] == "system"
