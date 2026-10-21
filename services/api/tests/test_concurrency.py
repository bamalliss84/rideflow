"""Concurrency scenarios (TEST_PLAN §2, T6) using real parallel transactions on PostgreSQL."""

import threading

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection

from apps.core.context import tenant_context
from apps.rides.models import Ride
from apps.subscriptions.models import DriverSubscription

from .factories import PNG, api_for, make_driver, make_member, make_tenant, ride_payload

pytestmark = pytest.mark.django_db(transaction=True)


def run_parallel(*calls):
    barrier = threading.Barrier(len(calls))
    results = [None] * len(calls)

    def runner(index, call):
        try:
            barrier.wait()
            results[index] = call()
        finally:
            connection.close()

    threads = [threading.Thread(target=runner, args=(i, c)) for i, c in enumerate(calls)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return results


def test_two_riders_select_same_driver_only_one_wins():
    t = make_tenant("conc1")
    driver = make_driver(t)
    driver_api = api_for(t, driver.user)
    riders = [api_for(t, make_member(t, "rider")) for _ in range(2)]
    rides = [r.post("/api/v1/rides", ride_payload(t)).data for r in riders]
    bids = [driver_api.post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 1000, "eta_seconds": 60}).data for ride in rides]
    responses = run_parallel(
        *[
            (
                lambda api=api, ride=ride, bid=bid: api.post(
                    f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]}
                )
            )
            for api, ride, bid in zip(riders, rides, bids, strict=True)
        ]
    )
    codes = sorted(r.status_code for r in responses)
    assert codes == [200, 409], [r.data for r in responses]
    loser = next(r for r in responses if r.status_code == 409)
    assert loser.data["code"] in ("driver_unavailable", "bid_not_open")
    with tenant_context(t.tenant):
        assert Ride.objects.filter(driver=driver, status="match_pending").count() == 1


def test_duplicate_selection_requests_produce_one_match():
    t = make_tenant("conc2")
    d1, d2 = make_driver(t), make_driver(t, offset=(0.002, 0.0))
    rider_api = api_for(t, make_member(t, "rider"))
    ride = rider_api.post("/api/v1/rides", ride_payload(t)).data
    b1 = api_for(t, d1.user).post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 1000, "eta_seconds": 60}).data
    b2 = api_for(t, d2.user).post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 900, "eta_seconds": 60}).data
    responses = run_parallel(
        lambda: rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": b1["id"], "expected_version": 2}),
        lambda: rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": b2["id"], "expected_version": 2}),
    )
    assert sorted(r.status_code for r in responses) == [200, 409]
    with tenant_context(t.tenant):
        assert Ride.objects.get(pk=ride["id"]).status == "match_pending"


def test_same_idempotency_key_in_parallel_executes_once():
    t = make_tenant("conc3")
    make_driver(t)
    rider_api = api_for(t, make_member(t, "rider"))
    body = ride_payload(t)
    responses = run_parallel(*[lambda: rider_api.post("/api/v1/rides", body, key="parallel-key")] * 3)
    assert {r.status_code for r in responses} == {201}
    assert len({r.data["id"] for r in responses}) == 1
    with tenant_context(t.tenant):
        assert Ride.objects.count() == 1


def test_two_admins_approving_same_claim_create_one_subscription():
    t = make_tenant("conc4")
    driver = make_driver(t, subscribed=False)
    claim = (
        api_for(t, driver.user)
        .post(
            "/api/v1/driver/deposit-claims",
            {
                "plan_id": str(t.monthly.pk),
                "deposit_account_id": str(t.account.pk),
                "amount_minor": 500000,
                "reference": "REF-RACE",
                "deposited_on": "2026-10-20",
                "receipt": SimpleUploadedFile("r.png", PNG),
            },
            fmt="multipart",
        )
        .data
    )
    admins = [api_for(t, make_member(t, "finance")) for _ in range(2)]
    responses = run_parallel(*[(lambda a=a: a.post(f"/api/v1/admin/deposit-claims/{claim['id']}/approve")) for a in admins])
    assert sorted(r.status_code for r in responses) == [200, 409]
    with tenant_context(t.tenant):
        assert DriverSubscription.objects.filter(driver=driver).count() == 1


def test_parallel_driver_confirmations_single_assignment():
    t = make_tenant("conc5")
    driver = make_driver(t)
    driver_api = api_for(t, driver.user)
    rider_api = api_for(t, make_member(t, "rider"))
    ride = rider_api.post("/api/v1/rides", ride_payload(t)).data
    bid = driver_api.post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 1000, "eta_seconds": 60}).data
    selected = rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]}).data
    responses = run_parallel(
        *[(lambda: driver_api.post(f"/api/v1/rides/{ride['id']}/confirm", {"expected_version": selected["version"]}))] * 2
    )
    assert sorted(r.status_code for r in responses) == [200, 409]
    with tenant_context(t.tenant):
        ride_obj = Ride.objects.get(pk=ride["id"])
        assert ride_obj.status == "assigned"
        assert ride_obj.events.filter(event_type="confirm").count() == 1
