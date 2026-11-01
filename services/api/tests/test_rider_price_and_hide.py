import pytest

from apps.geo.services import _round_to_unit, rider_price_minimum

from .factories import api_for, make_driver, make_member, make_tenant, ride_payload

pytestmark = pytest.mark.django_db


def _setup(slug):
    t = make_tenant(slug)
    driver = make_driver(t)
    return t, api_for(t, driver.user), api_for(t, make_member(t, "rider"))


def test_estimate_is_rounded_and_reports_the_rider_minimum():
    t, _driver, rider = _setup("price-round")
    ride = rider.post("/api/v1/rides", ride_payload(t)).data
    assert ride["estimate"]["min_minor"] % 100 == 0
    assert ride["estimate"]["max_minor"] % 100 == 0
    assert ride["rider_price_minor"] is None


def test_rider_minimum_never_falls_below_the_percentage():
    policy = {"fare.round_unit_minor": 100, "fare.rider_min_pct": 90}
    assert rider_price_minimum(73500, policy) == 66200  # 661.50 rounds UP to 662
    assert rider_price_minimum(73500, {**policy, "fare.rider_min_pct": 100}) == 73500
    assert _round_to_unit(73512, 100) == 73500
    assert _round_to_unit(110268, 100) == 110300


def test_rider_price_is_optional_validated_and_shown_to_the_driver():
    t, driver, rider = _setup("price-show")
    low = rider.post("/api/v1/rides", {**ride_payload(t), "rider_price_minor": 100})
    assert low.status_code == 422 and low.data["code"] == "rider_price_too_low"

    priced = rider.post("/api/v1/rides", {**ride_payload(t), "rider_price_minor": 10_000_000})
    assert priced.status_code == 201, priced.data
    assert priced.data["rider_price_minor"] == 10_000_000
    offers = driver.get("/api/v1/driver/ride-offers").data
    assert offers[0]["rider_price_minor"] == 10_000_000
    assert offers[0]["estimate"]["label"] == "estimate, not guaranteed"
    assert offers[0]["agreed_fare_minor"] is None  # a proposal is never the final fare


def test_new_user_rating_is_provisional_for_the_other_party():
    t, driver, rider = _setup("rating-new")
    rider.post("/api/v1/rides", ride_payload(t))
    trust = driver.get("/api/v1/driver/ride-offers").data[0]["rider"]["trust"]
    assert trust["rating_count"] == 0 and trust["rating_provisional"] is True


def test_hiding_affects_only_that_driver_and_can_be_undone():
    t, driver, rider = _setup("hide-one")
    other = api_for(t, make_driver(t).user)
    ride = rider.post("/api/v1/rides", ride_payload(t)).data

    assert driver.post(f"/api/v1/driver/ride-offers/{ride['id']}/hide").status_code == 204
    assert driver.post(f"/api/v1/driver/ride-offers/{ride['id']}/hide").status_code == 204  # repeat is safe
    assert driver.get("/api/v1/driver/ride-offers").data == []
    assert driver.get("/api/v1/driver/ride-offers/hidden").data == {"count": 1}
    assert len(other.get("/api/v1/driver/ride-offers").data) == 1
    assert rider.get(f"/api/v1/rides/{ride['id']}").data["status"] == "bidding"

    assert driver.client.delete(f"/api/v1/driver/ride-offers/{ride['id']}/hide").status_code == 204
    assert len(driver.get("/api/v1/driver/ride-offers").data) == 1

    driver.post(f"/api/v1/driver/ride-offers/{ride['id']}/hide")
    assert driver.client.delete("/api/v1/driver/ride-offers/hidden").status_code == 204
    assert driver.get("/api/v1/driver/ride-offers/hidden").data == {"count": 0}


def test_cannot_hide_with_an_open_offer_or_a_request_not_sent_to_you():
    t, driver, rider = _setup("hide-guard")
    ride = rider.post("/api/v1/rides", ride_payload(t)).data
    bid = driver.post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 90000, "eta_seconds": 300})
    assert bid.status_code == 201, bid.data
    blocked = driver.post(f"/api/v1/driver/ride-offers/{ride['id']}/hide")
    assert blocked.status_code == 409 and blocked.data["code"] == "offer_has_open_bid"

    stranger = make_tenant("hide-guard-b")
    outsider = api_for(stranger, make_driver(stranger).user)
    assert outsider.post(f"/api/v1/driver/ride-offers/{ride['id']}/hide").status_code == 404
