"""Phone notifications through Firebase: which events get one, what it says, and that a failure never breaks a request."""

import json
from urllib.parse import parse_qs

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from apps.core.context import tenant_context
from apps.notifications import push
from apps.notifications.models import DeviceToken

pytestmark = pytest.mark.django_db


@pytest.fixture
def key_file(tmp_path):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
    path = tmp_path / "firebase-admin.json"
    path.write_text(
        json.dumps(
            {
                "type": "service_account",
                "project_id": "rideflow-test",
                "private_key_id": "k1",
                "private_key": pem,
                "client_email": "push@rideflow-test.iam.gserviceaccount.com",
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        )
    )
    return path, key.public_key()


@pytest.fixture
def fcm(settings, key_file, monkeypatch):
    """FCM switched on, Google replaced by a recorder, and the pool run inline."""
    settings.PUSH_PROVIDER = "fcm"
    settings.FIREBASE_CREDENTIALS_FILE = str(key_file[0])
    push._access.update(token=None, expires=0.0)
    calls = []
    replies = {}

    def fake_post(url, data, headers):
        calls.append((url, data, headers))
        if "oauth2" in url:
            return 200, json.dumps({"access_token": "at-1", "expires_in": 3600})
        token = json.loads(data)["message"]["token"]
        return replies.get(token, (200, "{}"))

    monkeypatch.setattr(push, "_post", fake_post)
    monkeypatch.setattr(push._pool, "submit", lambda fn, *a: fn(*a))
    return calls, replies, key_file[1]


def sent(calls):
    return [json.loads(data)["message"] for url, data, _ in calls if "fcm.googleapis.com" in url]


def add_token(tenant, user, token):
    with tenant_context(tenant):
        DeviceToken.objects.create(user=user, token=token, platform="android")


def test_a_driver_hears_of_a_new_request_with_the_app_closed(ride_flow, fcm, django_capture_on_commit_callbacks):
    calls, _, public_key = fcm
    f = ride_flow
    add_token(f.tenant.tenant, f.driver1.user, "phone-d1")
    with django_capture_on_commit_callbacks(execute=True):
        f.create()
    messages = sent(calls)
    offers = [m for m in messages if m["data"]["kind"] == "ride.offer"]
    assert offers and offers[0]["token"] == "phone-d1"
    assert offers[0]["notification"]["title"] == "طلب جديد قريب منك"
    assert offers[0]["android"]["notification"]["channel_id"] == "rides"
    assert offers[0]["android"]["priority"] == "HIGH"
    # The access token comes from an assertion signed with the service account key, for the FCM scope only.
    url, body, _ = calls[0]
    assertion = parse_qs(body.decode())["assertion"][0]
    claims = jwt.decode(assertion, public_key, algorithms=["RS256"], audience="https://oauth2.googleapis.com/token")
    assert claims["scope"] == push.FCM_SCOPE
    assert [h for u, _, h in calls if "fcm.googleapis.com" in u][0]["Authorization"] == "Bearer at-1"


def test_the_rider_hears_of_each_offer(ride_flow, fcm, django_capture_on_commit_callbacks):
    calls, _, _ = fcm
    f = ride_flow
    add_token(f.tenant.tenant, f.rider_user, "phone-rider")
    with django_capture_on_commit_callbacks(execute=True):
        ride = f.create()
    with django_capture_on_commit_callbacks(execute=True):
        f.bid(ride["id"])
    kinds = [m["data"]["kind"] for m in sent(calls) if m["token"] == "phone-rider"]
    assert "ride.bid_created" in kinds
    assert "ride.dispatched" not in kinds, "progress hints stay silent"


def test_events_without_text_send_nothing():
    assert push.build_message("ride.dispatched", {"ride_id": "x"}) is None
    message = push.build_message("ride.bid_created", {"ride_id": "r1", "status": "bidding", "version": 3})
    assert message["data"] == {"kind": "ride.bid_created", "ride_id": "r1", "status": "bidding", "version": "3"}
    assert message["android"]["notification"]["tag"] == "r1:ride"
    assert push.build_message("ride.bid_created", {"ride_id": "r1"}, "en")["notification"]["title"] == "You have a new offer"


def test_a_removed_app_loses_its_token(ride_flow, fcm, django_capture_on_commit_callbacks):
    calls, replies, _ = fcm
    f = ride_flow
    add_token(f.tenant.tenant, f.driver1.user, "gone")
    replies["gone"] = (404, json.dumps({"error": {"status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}}))
    with django_capture_on_commit_callbacks(execute=True):
        f.create()
    with tenant_context(f.tenant.tenant):
        assert not DeviceToken.objects.filter(token="gone").exists()


def test_google_failing_never_breaks_the_request(ride_flow, fcm, django_capture_on_commit_callbacks, monkeypatch):
    f = ride_flow
    add_token(f.tenant.tenant, f.driver1.user, "phone-d1")

    def broken(*a):
        raise OSError("network down")

    monkeypatch.setattr(push, "_post", broken)
    with django_capture_on_commit_callbacks(execute=True):
        ride = f.create()
    assert ride is not None


def test_without_the_key_nothing_is_sent(ride_flow, fcm, django_capture_on_commit_callbacks, settings):
    calls, _, _ = fcm
    settings.FIREBASE_CREDENTIALS_FILE = "/nowhere/firebase-admin.json"
    f = ride_flow
    add_token(f.tenant.tenant, f.driver1.user, "phone-d1")
    with django_capture_on_commit_callbacks(execute=True):
        f.create()
    assert calls == []
