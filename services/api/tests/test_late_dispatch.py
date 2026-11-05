from datetime import timedelta

import pytest
from django.utils import timezone

from apps.core.context import tenant_context
from apps.geo.models import DriverLocation
from apps.rides.models import Ride

pytestmark = pytest.mark.django_db


def _offline(api):
    assert api.post("/api/v1/driver/availability", {"online": False}).status_code == 200


def _online(api):
    r = api.post("/api/v1/driver/availability", {"online": True})
    assert r.status_code == 200, r.data


def _offer_ids(api):
    return [r["id"] for r in api.get("/api/v1/driver/ride-offers").data]


def _make_location_stale(f, driver):
    with tenant_context(f.tenant.tenant):
        DriverLocation.objects.filter(driver=driver).update(server_ts=timezone.now() - timedelta(hours=1))


def _ping(f, api, dx=0.001):
    lng, lat = f.tenant.center
    r = api.post("/api/v1/driver/location", {"lat": lat + dx, "lng": lng + dx, "accuracy_m": 10})
    assert r.data["applied"] is True


def test_going_online_brings_up_a_request_made_while_offline(ride_flow):
    f = ride_flow
    _offline(f.d1_api)
    ride = f.create()
    assert _offer_ids(f.d1_api) == []
    _online(f.d1_api)
    assert _offer_ids(f.d1_api) == [ride["id"]]
    f.bid(ride["id"])


def test_a_request_nobody_heard_starts_taking_offers_when_a_driver_arrives(ride_flow):
    f = ride_flow
    _offline(f.d1_api)
    _offline(f.d2_api)
    ride = f.create()
    assert f.snapshot(ride["id"])["status"] == "requested"
    _online(f.d1_api)
    assert f.snapshot(ride["id"])["status"] == "bidding"
    assert _offer_ids(f.d1_api) == [ride["id"]]


def test_coming_back_after_the_location_went_stale_brings_it_up(ride_flow):
    f = ride_flow
    _make_location_stale(f, f.driver1)
    ride = f.create()
    assert _offer_ids(f.d1_api) == []
    _ping(f, f.d1_api)
    assert _offer_ids(f.d1_api) == [ride["id"]]


def test_a_request_beyond_the_last_wave_stays_away(ride_flow):
    f = ride_flow
    _make_location_stale(f, f.driver1)
    f.create()
    _ping(f, f.d1_api, dx=0.2)  # about 30 km; the last wave reaches 7 km
    assert _offer_ids(f.d1_api) == []


def test_a_timed_out_request_stays_away(ride_flow):
    f = ride_flow
    _make_location_stale(f, f.driver1)
    old = f.create()
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=old["id"]).update(created_at=timezone.now() - timedelta(hours=2))
    _ping(f, f.d1_api)
    assert old["id"] not in _offer_ids(f.d1_api)


def test_a_driver_on_a_trip_gets_nothing_new(ride_flow, h):
    f = ride_flow
    f.assigned()
    second = h.api(f.tenant, h.member(f.tenant, "rider", name="Second"))
    other = second.post("/api/v1/rides", h.ride_payload(f.tenant))
    assert other.status_code == 201, other.data
    _ping(f, f.d1_api)
    assert _offer_ids(f.d1_api) == []


def test_a_hidden_request_does_not_come_back(ride_flow):
    f = ride_flow
    ride = f.create()
    assert f.d1_api.post(f"/api/v1/driver/ride-offers/{ride['id']}/hide").status_code == 204
    _ping(f, f.d1_api)
    _online(f.d1_api)
    assert _offer_ids(f.d1_api) == []


def test_the_driver_is_added_once(ride_flow):
    f = ride_flow
    _offline(f.d1_api)
    ride = f.create()
    _online(f.d1_api)
    _ping(f, f.d1_api)
    _ping(f, f.d1_api)
    with tenant_context(f.tenant.tenant):
        assert Ride.objects.get(pk=ride["id"]).candidates.filter(driver=f.driver1).count() == 1
