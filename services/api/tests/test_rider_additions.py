from datetime import timedelta

import pytest
from django.conf import settings as dj_settings
from django.core import signing
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.core.context import tenant_context
from apps.geo.models import SavedPlace
from apps.rides.models import Ride, RideEvent
from apps.rides.services import SHARE_TOKEN_SALT, read_share_token
from apps.tenancy.models import AppType
from apps.tenancy.services import create_config_version

pytestmark = pytest.mark.django_db


def overrides(t, **params):
    with tenant_context(t.tenant):
        create_config_version(overrides={k.replace("__", "."): v for k, v in params.items()})


def payload(h, t, **extra):
    return {**h.ride_payload(t), **extra}


def test_stop_descriptions_reach_the_driver_only_after_the_match(ride_flow, h):
    f = ride_flow
    r = f.rider_api.post("/api/v1/rides", payload(h, f.tenant, pickup_note="عند البوابة الزرقاء", dropoff_note="خلف المستشفى"))
    assert r.status_code == 201, r.data
    ride = r.data
    assert ride["pickup_note"] == "عند البوابة الزرقاء" and ride["dropoff_note"] == "خلف المستشفى"
    assert f.rider_api.post("/api/v1/rides", payload(h, f.tenant, pickup_note="x" * 301)).status_code == 400

    offered = f.d1_api.get("/api/v1/driver/ride-offers").data
    listed = next(o for o in offered if o["id"] == ride["id"])
    assert listed["pickup_note"] == "" and listed["dropoff_note"] == ""

    bid = f.bid(ride["id"])
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/confirm", {"expected_version": r.data["version"]})
    assert r.status_code == 200, r.data
    assert r.data["pickup_note"] == "عند البوابة الزرقاء" and r.data["dropoff_note"] == "خلف المستشفى"


def assigned_with_code(f, h):
    r = f.rider_api.post("/api/v1/rides", payload(h, f.tenant, require_start_code=True))
    assert r.status_code == 201, r.data
    ride = r.data
    bid = f.bid(ride["id"])
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/confirm", {"expected_version": r.data["version"]})
    assert r.status_code == 200, r.data
    return r.data


def arrive(f, ride):
    lng, lat = f.tenant.center
    r = f.d1_api.post(
        f"/api/v1/rides/{ride['id']}/arrive",
        {"expected_version": ride["version"], "lat": lat, "lng": lng, "accuracy_m": 10.0, "device_ts": timezone.now().isoformat()},
    )
    assert r.status_code == 200, r.data
    return r.data


# ---------------------------------------------------------------- live position


def test_rider_follows_the_matched_driver_and_nobody_else_can(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.rider_api.get(f"/api/v1/rides/{ride['id']}/driver-location")
    assert r.status_code == 200, r.data
    assert set(r.data) == {"lat", "lng", "heading", "age_seconds", "stale"} and r.data["stale"] is False
    assert f.d1_api.get(f"/api/v1/rides/{ride['id']}/driver-location").status_code == 403
    assert f.d2_api.get(f"/api/v1/rides/{ride['id']}/driver-location").status_code in (403, 404)


def test_no_driver_position_before_a_match(ride_flow):
    f = ride_flow
    ride = f.create()
    assert f.rider_api.get(f"/api/v1/rides/{ride['id']}/driver-location").status_code == 404


# ---------------------------------------------------------------- cancellation


def test_snapshot_says_when_free_cancelling_ends_and_reason_codes_are_kept(ride_flow):
    f = ride_flow
    ride = f.assigned()
    assert ride["free_cancel_until"] is not None
    r = f.rider_api.post(
        f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"], "reason": "changed", "reason_code": "changed_mind"}
    )
    assert r.status_code == 200, r.data
    assert r.data["cancellation"]["reason_code"] == "changed_mind"
    assert r.data["free_cancel_until"] is None


def test_unknown_cancel_reason_code_is_refused(ride_flow):
    f = ride_flow
    ride = f.create()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"], "reason_code": "nope"})
    assert r.status_code == 400


# ---------------------------------------------------------------- start code


def test_only_the_rider_sees_the_start_code_and_the_trip_needs_it(ride_flow, h):
    f = ride_flow
    ride = assigned_with_code(f, h)
    code = ride_rider = f.snapshot(ride["id"])["start_code"]
    assert len(ride_rider) == 4
    driver_view = f.snapshot(ride["id"], api=f.d1_api)
    assert driver_view["start_code"] is None and driver_view["start_code_required"] is True
    ride = arrive(f, driver_view)

    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"]})
    assert r.status_code == 422 and r.data["code"] == "start_code_invalid"
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"], "start_code": code})
    assert r.status_code == 200, r.data
    assert r.data["status"] == "in_progress"
    assert f.snapshot(ride["id"])["start_code"] is None
    with tenant_context(f.tenant.tenant):
        for event in RideEvent.objects.filter(ride_id=ride["id"]):
            assert code not in str(event.data)


def test_too_many_wrong_codes_lock_the_start_and_the_lock_passes(ride_flow, h):
    f = ride_flow
    ride = arrive(f, assigned_with_code(f, h))
    code = f.snapshot(ride["id"])["start_code"]
    wrong = "0000" if code != "0000" else "1111"
    url = f"/api/v1/rides/{ride['id']}/start"
    for _ in range(5):
        r = f.d1_api.post(url, {"expected_version": ride["version"], "start_code": wrong})
        assert r.data["code"] == "start_code_invalid"
    r = f.d1_api.post(url, {"expected_version": ride["version"], "start_code": code})
    assert r.status_code == 422 and r.data["code"] == "start_code_locked"
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(start_code_failed_at=timezone.now() - timedelta(minutes=6))
    r = f.d1_api.post(url, {"expected_version": ride["version"], "start_code": code})
    assert r.status_code == 200, r.data


def test_a_ride_without_a_code_starts_as_before(ride_flow):
    f = ride_flow
    ride = f.arrived()
    assert ride["start_code_required"] is False
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"]})
    assert r.status_code == 200, r.data


def test_operator_can_require_a_code_for_every_ride(ride_flow, h):
    f = ride_flow
    overrides(f.tenant, rides__start_code_required=True)
    assert f.create()["start_code_required"] is True


# ---------------------------------------------------------------- sharing


def test_shared_link_shows_the_trip_without_a_sign_in_and_no_phone_numbers(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/share")
    assert r.status_code == 201, r.data
    token = r.data["token"]
    assert f.snapshot(ride["id"])["share_active"] is True

    r = APIClient().get(f"/api/v1/public/trips/{token}")
    assert r.status_code == 200, r.data
    assert r.data["active"] is True and r.data["vehicle"]["plate_number"] and r.data["position"]["lat"]
    assert r["Cache-Control"] == "no-store"
    assert f.driver1.user.phone not in str(r.data) and f.rider_user.phone not in str(r.data)


def test_shared_link_shows_nothing_after_the_trip_or_once_stopped(ride_flow):
    f = ride_flow
    ride = f.assigned()
    token = f.rider_api.post(f"/api/v1/rides/{ride['id']}/share").data["token"]
    assert f.rider_api.client.delete(f"/api/v1/rides/{ride['id']}/share").status_code == 204
    assert APIClient().get(f"/api/v1/public/trips/{token}").status_code == 404

    token = f.rider_api.post(f"/api/v1/rides/{ride['id']}/share").data["token"]
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    r = APIClient().get(f"/api/v1/public/trips/{token}")
    assert r.status_code == 200
    assert r.data == {
        "status": "cancelled",
        "active": False,
        "dropoff_landmark": None,
        "driver_name": None,
        "vehicle": None,
        "position": None,
    }


def test_a_share_id_signed_for_another_tenant_finds_nothing(ride_flow, tb):
    f = ride_flow
    ride = f.assigned()
    token = f.rider_api.post(f"/api/v1/rides/{ride['id']}/share").data["token"]
    _, share_id = read_share_token(token)
    crossed = signing.dumps({"t": str(tb.tenant.pk), "s": share_id}, salt=SHARE_TOKEN_SALT)
    assert APIClient().get(f"/api/v1/public/trips/{crossed}").status_code == 404


def test_forged_share_links_and_other_users_are_refused(ride_flow, tb, h):
    f = ride_flow
    ride = f.assigned()
    assert APIClient().get("/api/v1/public/trips/not-a-token").status_code == 404
    token = f.rider_api.post(f"/api/v1/rides/{ride['id']}/share").data["token"]
    assert APIClient().get(f"/api/v1/public/trips/{token[:-1]}x").status_code == 404
    assert f.d1_api.post(f"/api/v1/rides/{ride['id']}/share").status_code == 403
    other = h.api(tb, h.member(tb, "rider"))
    assert other.post(f"/api/v1/rides/{ride['id']}/share").status_code == 404


# ---------------------------------------------------------------- emergency


def test_emergency_is_recorded_alerts_staff_and_returns_the_number(ride_flow, h):
    f = ride_flow
    overrides(f.tenant, safety__emergency_phone="+967199")
    staff = h.member(f.tenant, "owner")
    ride = f.assigned()
    assert f.snapshot(ride["id"])["emergency_phone"] == "+967199"
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/emergency", {"location": {"lat": 14.5, "lng": 49.1}})
    assert r.status_code == 200, r.data
    assert r.data == {"recorded": True, "emergency_phone": "+967199"}
    with tenant_context(f.tenant.tenant):
        event = RideEvent.objects.get(ride_id=ride["id"], event_type="emergency")
        assert event.data == {"by": "rider", "lat": 14.5, "lng": 49.1}
    kinds = [n["kind"] for n in h.api(f.tenant, staff).get("/api/v1/notifications").data["items"]]
    assert "ride.emergency" in kinds


def test_emergency_number_is_empty_until_configured_and_only_during_a_trip(ride_flow):
    f = ride_flow
    ride = f.create()
    assert f.snapshot(ride["id"])["emergency_phone"] is None
    assert f.rider_api.post(f"/api/v1/rides/{ride['id']}/emergency", {}).status_code == 409


# ---------------------------------------------------------------- raising the price


def test_rider_raises_the_price_and_drivers_are_told(ride_flow):
    f = ride_flow
    ride = f.create()
    target = ride["estimate"]["max_minor"]
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/raise-price", {"expected_version": ride["version"], "amount_minor": target})
    assert r.status_code == 200, r.data
    assert r.data["rider_price_minor"] == target and r.data["version"] == ride["version"] + 1
    assert any(n["kind"] == "ride.price_raised" for n in f.d1_api.get("/api/v1/notifications").data["items"])
    offers = {o["id"]: o for o in f.d1_api.get("/api/v1/driver/ride-offers").data}
    assert offers[ride["id"]]["rider_price_minor"] == target


def test_the_price_cannot_go_down_or_change_after_selecting(ride_flow):
    f = ride_flow
    ride = f.create()
    high = ride["estimate"]["max_minor"]
    url = f"/api/v1/rides/{ride['id']}/raise-price"
    version = f.rider_api.post(url, {"expected_version": ride["version"], "amount_minor": high}).data["version"]
    r = f.rider_api.post(url, {"expected_version": version, "amount_minor": high})
    assert r.status_code == 422 and r.data["code"] == "rider_price_too_low"
    r = f.rider_api.post(url, {"expected_version": ride["version"], "amount_minor": high + 100})
    assert r.status_code == 409

    done = f.d1_api.post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 150000, "eta_seconds": 300})
    snap = f.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": done.data["id"], "expected_version": version})
    r = f.rider_api.post(url, {"expected_version": snap.data["version"], "amount_minor": high + 100})
    assert r.status_code == 409


def test_a_driver_cannot_raise_the_price(ride_flow):
    f = ride_flow
    ride = f.create()
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/raise-price", {"expected_version": ride["version"], "amount_minor": 999999})
    assert r.status_code == 403


# ---------------------------------------------------------------- saved and recent places


def place(**extra):
    return {"kind": "other", "label": "الجامعة", "landmark": "جامعة حضرموت", "point": {"lat": 14.55, "lng": 49.13}, **extra}


def test_saved_places_belong_to_their_rider(ta, tb, h):
    rider = h.member(ta, "rider")
    api = h.api(ta, rider)
    r = api.post("/api/v1/me/places", place())
    assert r.status_code == 201, r.data
    assert api.get("/api/v1/me/places").data[0]["landmark"] == "جامعة حضرموت"
    place_id = r.data["id"]
    other = h.api(ta, h.member(ta, "rider"))
    assert other.get("/api/v1/me/places").data == []
    assert other.client.delete(f"/api/v1/me/places/{place_id}").status_code == 404
    foreign = h.api(tb, h.member(tb, "rider"))
    assert foreign.get(f"/api/v1/me/places/{place_id}").status_code == 404
    assert api.client.delete(f"/api/v1/me/places/{place_id}").status_code == 204


def test_one_home_per_rider_and_a_limit_on_places(ta, h):
    api = h.api(ta, h.member(ta, "rider"))
    assert api.post("/api/v1/me/places", place(kind="home")).status_code == 201
    r = api.post("/api/v1/me/places", place(kind="home"))
    assert r.status_code == 409 and r.data["code"] == "place_kind_exists"
    for _ in range(19):
        assert api.post("/api/v1/me/places", place()).status_code == 201
    r = api.post("/api/v1/me/places", place())
    assert r.status_code == 409 and r.data["code"] == "places_limit"


def test_drivers_have_no_saved_places(ride_flow):
    assert ride_flow.d1_api.get("/api/v1/me/places").status_code == 403


def test_recent_places_come_from_the_riders_own_rides(ride_flow, h):
    f = ride_flow
    ride = f.create()
    rows = f.rider_api.get("/api/v1/me/recent-places").data
    assert [row["landmark"] for row in rows] == [ride["dropoff_landmark"]]
    assert h.api(f.tenant, h.member(f.tenant, "rider")).get("/api/v1/me/recent-places").data == []


# ---------------------------------------------------------------- devices


def test_a_device_token_moves_to_whoever_signed_in_last(ride_flow, h):
    f = ride_flow
    body = {"token": "device-1", "platform": "android"}
    assert f.rider_api.post("/api/v1/me/devices", body).status_code == 204
    other = h.api(f.tenant, h.member(f.tenant, "rider"))
    assert other.post("/api/v1/me/devices", body).status_code == 204
    from apps.notifications.models import DeviceToken

    with tenant_context(f.tenant.tenant):
        assert DeviceToken.objects.get(token="device-1").user != f.rider_user
    assert other.client.delete("/api/v1/me/devices", {"token": "device-1"}, format="json").status_code == 204
    with tenant_context(f.tenant.tenant):
        assert not DeviceToken.objects.exists()


def test_notifications_still_work_with_no_push_provider(ride_flow):
    f = ride_flow
    assert dj_settings.PUSH_PROVIDER == "none"
    f.create()
    assert f.d1_api.get("/api/v1/notifications").data["items"]


# ---------------------------------------------------------------- account deletion


def request_code(t, phone):
    client = APIClient()
    r = client.post("/api/v1/auth/otp/request", {"phone": phone}, HTTP_X_RIDEFLOW_APP=t.apps[AppType.RIDER].client_id)
    assert r.status_code < 300, r.data
    return dj_settings.OTP_DEV_CODE


def test_deleting_an_account_erases_the_person_and_keeps_the_ride_record(ride_flow):
    f = ride_flow
    ride = f.create()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/cancel", {"expected_version": ride["version"]})
    assert r.status_code == 200, r.data
    f.rider_api.post("/api/v1/me/places", place(kind="home"))
    phone = f.rider_user.phone
    code = request_code(f.tenant, phone)

    assert f.rider_api.post("/api/v1/me/delete-account", {"code": "bad"}).status_code == 400
    assert User.objects.get(pk=f.rider_user.pk).is_active

    r = f.rider_api.post("/api/v1/me/delete-account", {"code": code})
    assert r.status_code == 204, getattr(r, "data", None)
    user = User.objects.get(pk=f.rider_user.pk)
    assert not user.is_active and user.full_name == "" and user.phone != phone
    with tenant_context(f.tenant.tenant):
        assert Ride.objects.filter(pk=ride["id"]).exists()
        assert not SavedPlace.objects.exists()
    assert f.rider_api.get("/api/v1/me").status_code in (401, 403)


def test_an_active_ride_blocks_deleting_the_account(ride_flow):
    f = ride_flow
    f.create()
    r = f.rider_api.post("/api/v1/me/delete-account", {"code": "000000"})
    assert r.status_code == 409 and r.data["code"] == "active_ride_exists"
    assert User.objects.get(pk=f.rider_user.pk).is_active


def test_a_driver_cannot_delete_through_the_rider_route(ride_flow):
    assert ride_flow.d1_api.post("/api/v1/me/delete-account", {"code": "000000"}).status_code == 403


def test_a_rider_who_also_drives_goes_through_the_operator(ride_flow, h):
    f = ride_flow
    h.roles(f.tenant, f.rider_user, "driver")
    api = h.api(f.tenant, f.rider_user)
    r = api.post("/api/v1/me/delete-account", {"code": "000000"})
    assert r.status_code == 409 and r.data["code"] == "account_has_other_roles"


def test_a_rider_of_another_operator_keeps_that_account(ta, tb, h):
    user = h.member(ta, "rider")
    h.roles(tb, user, "rider")
    code = request_code(ta, user.phone)
    assert h.api(ta, user).post("/api/v1/me/delete-account", {"code": code}).status_code == 204
    fresh = User.objects.get(pk=user.pk)
    assert fresh.is_active and fresh.phone == user.phone
    assert h.api(tb, fresh).get("/api/v1/me/places").status_code == 200
