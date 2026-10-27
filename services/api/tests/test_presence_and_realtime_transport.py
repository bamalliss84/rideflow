"""Driver presence (GPS -> API -> PostGIS) and the realtime transport configuration (P0 fixes, Phase 4)."""

from datetime import timedelta

import pytest
from django.utils import timezone

from apps.core.context import system_context, tenant_context
from apps.geo.models import DriverLocation

from .factories import api_for, make_driver, make_member

pytestmark = pytest.mark.django_db


def test_location_is_stored_with_accuracy_device_and_server_time_in_the_drivers_tenant(ta, tb):
    driver = make_driver(ta, online=False, located=False)
    api = api_for(ta, driver.user)
    lng, lat = ta.center
    device_ts = timezone.now() - timedelta(seconds=3)
    r = api.post("/api/v1/driver/location", {"lat": lat, "lng": lng, "accuracy_m": 7.5, "device_ts": device_ts.isoformat()})
    assert r.status_code == 200 and r.data["applied"] is True
    with system_context():
        loc = DriverLocation.all_tenants.get(driver=driver)
    assert loc.tenant_id == ta.tenant.pk  # stored in the operator of the authenticated driver
    assert (round(loc.point.y, 6), round(loc.point.x, 6)) == (round(lat, 6), round(lng, 6))
    assert loc.accuracy_m == 7.5
    assert abs((loc.device_ts - device_ts).total_seconds()) < 1
    assert (timezone.now() - loc.server_ts).total_seconds() < 5
    with tenant_context(tb.tenant):
        assert not DriverLocation.objects.filter(driver_id=driver.pk).exists()


def test_going_online_requires_a_fresh_location_and_eligibility_reports_presence(ta):
    driver = make_driver(ta, online=False, located=False)
    api = api_for(ta, driver.user)
    e = api.get("/api/v1/driver/eligibility").data
    assert e["eligible"] is True and e["presence"] == {
        "has_location": False,
        "fresh": False,
        "server_ts": None,
        "accuracy_m": None,
        "stale_after_seconds": e["presence"]["stale_after_seconds"],
    }
    r = api.post("/api/v1/driver/availability", {"online": True})
    assert r.status_code == 403 and r.data["detail"]["reasons"] == ["location_required"]

    lng, lat = ta.center
    api.post("/api/v1/driver/location", {"lat": lat, "lng": lng, "accuracy_m": 10})
    assert api.post("/api/v1/driver/availability", {"online": True}).status_code == 200

    # A stale fix (older than presence.stale_seconds) is not "ready": refused again, and reported as not fresh.
    with tenant_context(ta.tenant):
        DriverLocation.objects.filter(driver=driver).update(server_ts=timezone.now() - timedelta(hours=1))
    assert api.post("/api/v1/driver/availability", {"online": False}).status_code == 200
    r = api.post("/api/v1/driver/availability", {"online": True})
    assert r.status_code == 403 and r.data["detail"]["reasons"] == ["location_required"]
    assert api.get("/api/v1/driver/eligibility").data["presence"]["fresh"] is False


def test_online_driver_with_fresh_location_appears_in_live_drivers_and_stale_one_does_not(ta, tb):
    owner_api = api_for(ta, make_member(ta, "owner"))
    driver = make_driver(ta, online=False, located=False)
    api = api_for(ta, driver.user)
    lng, lat = ta.center
    api.post("/api/v1/driver/location", {"lat": lat, "lng": lng, "accuracy_m": 10})
    assert api.post("/api/v1/driver/availability", {"online": True}).status_code == 200
    live = owner_api.get("/api/v1/admin/drivers-nearby", {"lat": lat, "lng": lng, "radius_m": 2000}).data
    assert str(driver.pk) in [str(d["driver_id"]) for d in live]
    # another operator never sees it
    other = api_for(tb, make_member(tb, "owner")).get("/api/v1/admin/drivers-nearby", {"lat": lat, "lng": lng, "radius_m": 2000}).data
    assert str(driver.pk) not in [str(d["driver_id"]) for d in other]
    with tenant_context(ta.tenant):
        DriverLocation.objects.filter(driver=driver).update(server_ts=timezone.now() - timedelta(hours=1))
    live = owner_api.get("/api/v1/admin/drivers-nearby", {"lat": lat, "lng": lng, "radius_m": 2000}).data
    assert str(driver.pk) not in [str(d["driver_id"]) for d in live]


def test_channel_layer_read_timeout_exceeds_the_blocking_receive():
    """Regression: redis-py 8 defaults socket_timeout to 5 s == channels_redis BRPOP wait -> WS dropped every ~5 s."""
    from channels_redis.core import RedisChannelLayer
    from channels_redis.utils import create_pool

    # The test settings use an in-memory layer; check the production/dev configuration itself.
    from rideflow import settings as base

    host = base.CHANNEL_LAYERS["default"]["CONFIG"]["hosts"][0]
    pool = create_pool(host)
    assert pool.connection_kwargs["socket_timeout"] > RedisChannelLayer.brpop_timeout + 5
    assert pool.connection_kwargs["socket_connect_timeout"] <= 10


@pytest.mark.asyncio
async def test_real_redis_channel_layer_survives_idle_receive_longer_than_brpop():
    """An idle receive across two BRPOP windows must not raise TimeoutError; a later message still arrives."""
    import asyncio

    from channels_redis.core import RedisChannelLayer

    from rideflow import settings as base

    layer = RedisChannelLayer(**base.CHANNEL_LAYERS["default"]["CONFIG"])
    try:
        channel = await layer.new_channel()
    except Exception as exc:  # pragma: no cover - no Redis reachable (e.g. isolated unit run)
        pytest.skip(f"Redis not reachable: {exc}")

    async def send_later():
        await asyncio.sleep(11)
        await layer.send(channel, {"type": "hint", "n": 1})

    sender = asyncio.create_task(send_later())
    message = await asyncio.wait_for(layer.receive(channel), timeout=30)
    await sender
    assert message == {"type": "hint", "n": 1}
    await layer.flush()
