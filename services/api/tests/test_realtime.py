"""WebSocket hints, reconnect replay and tenant-scoped delivery."""

import pytest
from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator

from rideflow.asgi import application

from .factories import add_roles, api_for, make_driver, make_member, make_tenant, ride_payload

pytestmark = [pytest.mark.django_db(transaction=True), pytest.mark.asyncio]


def _ws(token):
    return WebsocketCommunicator(
        application, f"/ws/v1/events/?token={token}", headers=[(b"host", b"localhost"), (b"origin", b"http://localhost")]
    )


async def test_websocket_requires_valid_token():
    communicator = _ws("not-a-token")
    connected, code = await communicator.connect()
    assert not connected or code == 4401
    await communicator.disconnect()


async def test_hint_delivery_and_resume_replay():
    @database_sync_to_async
    def setup():
        t = make_tenant("ws1")
        driver = make_driver(t)
        rider = make_member(t, "rider")
        return t, driver, rider, api_for(t, rider), api_for(t, driver.user)

    t, driver, rider, rider_api, driver_api = await setup()
    communicator = _ws(driver_api.tokens["access"])
    connected, _ = await communicator.connect()
    assert connected
    hello = await communicator.receive_json_from()
    assert hello["type"] == "hello"

    ride = await database_sync_to_async(lambda: rider_api.post("/api/v1/rides", ride_payload(t)).data)()
    hint = await communicator.receive_json_from(timeout=5)
    assert hint["type"] == "hint" and hint["kind"] == "ride.offer"
    assert hint["payload"]["ride_id"] == ride["id"]
    assert "pickup" not in hint["payload"]  # hints carry ids, not data
    await communicator.disconnect()

    # while disconnected the rider's bid notifications accumulate; reconnect + resume replays them
    await database_sync_to_async(
        lambda: driver_api.post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 1000, "eta_seconds": 60})
    )()
    rider_ws = _ws(rider_api.tokens["access"])
    await rider_ws.connect()
    await rider_ws.receive_json_from()
    await rider_ws.send_json_to({"type": "resume", "cursor": 0})
    kinds = []
    while True:
        message = await rider_ws.receive_json_from(timeout=5)
        if message["type"] == "resumed":
            break
        kinds.append(message["kind"])
    assert "ride.dispatched" in kinds and "ride.bid_created" in kinds
    await rider_ws.send_json_to({"type": "ping"})
    assert (await rider_ws.receive_json_from())["type"] == "pong"
    await rider_ws.disconnect()

    page = await database_sync_to_async(lambda: rider_api.get("/api/v1/notifications", {"after": 0}).data)()
    assert [i["kind"] for i in page["items"]] == kinds


async def test_hints_never_cross_tenants():
    @database_sync_to_async
    def setup():
        ta, tb = make_tenant("ws2a"), make_tenant("ws2b")
        user = make_member(ta, "rider")
        add_roles(tb, user, "rider")
        make_driver(ta)
        return ta, tb, user

    ta, tb, user = await setup()
    api_a = await database_sync_to_async(lambda: api_for(ta, user))()
    api_b = await database_sync_to_async(lambda: api_for(tb, user))()
    ws_b = _ws(api_b.tokens["access"])
    await ws_b.connect()
    await ws_b.receive_json_from()
    await database_sync_to_async(lambda: api_a.post("/api/v1/rides", ride_payload(ta)))()
    assert await ws_b.receive_nothing(timeout=1)
    await ws_b.send_json_to({"type": "resume", "cursor": 0})
    assert (await ws_b.receive_json_from())["type"] == "resumed"
    await ws_b.disconnect()
