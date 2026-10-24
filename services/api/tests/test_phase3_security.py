"""Phase 3 adversarial security suite: gaps not covered by the generated GET/POST isolation test."""

import importlib
import json

import pytest
from django.forms.models import model_to_dict
from django.urls import reverse
from rest_framework.test import APIClient

from apps.core import audit
from apps.core.context import tenant_context

from .factories import api_for, make_member
from .test_tenant_isolation import PUBLIC_ROUTES, _a_ids, _object_for, api_routes, two_tenants  # noqa: F401

pytestmark = pytest.mark.django_db

# A body that satisfies as many action serializers as possible, so an IDOR cannot hide behind a 400.
KITCHEN_SINK = {
    "note": "phase3 probe",
    "reason": "phase3 probe",
    "decision": "approve",
    "uphold": True,
    "approve": True,
    "verify": True,
    "status": "suspended",
    "stars": 5,
    "name": "probe",
    "is_active": False,
    "price_minor": 1,
    "duration_days": 1,
    "expected_version": 1,
    "amount_minor": 1,
    "eta_seconds": 60,
    "params": {"bids.expiry_seconds": 60},
}


def _snapshot(a):
    """Every tenant-A object the scenario created, as plain dicts read inside tenant A's context."""
    out = {}
    with tenant_context(a.t.tenant):
        for attr, obj in sorted(vars(a.objects).items()):
            if not hasattr(obj, "pk"):
                continue
            fresh = type(obj)._base_manager.filter(pk=obj.pk).first()
            out[attr] = json.dumps(model_to_dict(fresh) if fresh else None, default=str, sort_keys=True)
    return out


def _param_routes(a):
    for name, params in api_routes():
        if name in PUBLIC_ROUTES or not params:
            continue
        kwargs = {}
        for param in params:
            obj = _object_for(name, param, a.objects, a.t.tenant)
            if obj is None:
                break
            kwargs[param] = str(obj.pk)
        else:
            yield name, reverse(name, kwargs=kwargs)


def test_mutating_verbs_and_valid_bodies_on_other_tenant_objects_never_succeed(two_tenants):  # noqa: F811
    """PATCH/PUT/DELETE and well-formed action bodies against tenant A ids from a tenant B owner (MFA session)."""
    a, _b, attacker = two_tenants
    before = _snapshot(a)
    leaked = _a_ids(a)
    probed = 0
    for name, url in _param_routes(a):
        responses = [
            attacker.client.patch(url, KITCHEN_SINK, format="json"),
            attacker.client.put(url, KITCHEN_SINK, format="json"),
            attacker.client.delete(url),
            attacker.post(url, KITCHEN_SINK),
        ]
        for r in responses:
            probed += 1
            assert r.status_code in (400, 403, 404, 405), (name, url, r.request["REQUEST_METHOD"], r.status_code)
            if r.get("Content-Type", "").startswith("application/json"):
                body = r.content.decode(errors="ignore")
                assert not any(i in body for i in leaked), (name, "leaked tenant A data")
    assert probed >= 200, probed
    assert _snapshot(a) == before, "tenant A records changed"


def test_refresh_token_cannot_be_reused_after_rotation(ta):
    rider = make_member(ta, "rider")
    refresh = api_for(ta, rider).tokens["refresh"]
    first = APIClient().post("/api/v1/auth/token/refresh", {"refresh": refresh}, format="json")
    assert first.status_code == 200 and first.data["refresh"] != refresh
    replay = APIClient().post("/api/v1/auth/token/refresh", {"refresh": refresh}, format="json")
    assert replay.status_code == 401
    assert APIClient().post("/api/v1/auth/token/refresh", {"refresh": first.data["refresh"]}, format="json").status_code == 200


def test_tampered_and_foreign_tokens_are_rejected(ta, tb):
    owner = make_member(ta, "owner")
    access = api_for(ta, owner).tokens["access"]
    head, payload, sig = access.split(".")
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {head}.{payload}.{sig[:-2]}AA")
    assert client.get("/api/v1/me").status_code == 401
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {head}.{payload}.")  # alg-stripping style
    assert client.get("/api/v1/me").status_code == 401
    # a tenant A owner token used with tenant B's admin app header
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    assert client.get("/api/v1/admin/members", HTTP_X_RIDEFLOW_APP=tb.apps["admin"].client_id).status_code == 401


def test_page_size_is_capped(ta):
    owner = make_member(ta, "owner")
    with tenant_context(ta.tenant):
        for i in range(105):
            audit.record("phase3.page_cap", actor=owner, data={"i": i}, tenant_id=ta.tenant.pk)
    r = api_for(ta, owner).get("/api/v1/admin/audit-events", {"page_size": 100000, "action": "phase3."})
    assert r.status_code == 200 and r.data["count"] == 105 and len(r.data["results"]) == 100


def test_api_security_headers(ta):
    r = api_for(ta, make_member(ta, "rider")).get("/api/v1/me")
    assert r["X-Frame-Options"] == "DENY"
    assert r["X-Content-Type-Options"] == "nosniff"


def test_api_docs_are_disabled_unless_enabled(settings, client):
    from django.urls import clear_url_caches

    import rideflow.urls as urls

    settings.API_DOCS_ENABLED = False
    clear_url_caches()
    importlib.reload(urls)
    try:
        assert client.get("/api/schema/").status_code == 404
        assert client.get("/api/docs/").status_code == 404
    finally:
        settings.API_DOCS_ENABLED = True
        importlib.reload(urls)
        clear_url_caches()


@pytest.mark.parametrize(
    "env,match",
    [
        ({"DJANGO_SECRET_KEY": "short"}, "DJANGO_SECRET_KEY"),
        ({"DJANGO_SECRET_KEY": "dev-only-insecure-secret-key-change-me-0123456789"}, "DJANGO_SECRET_KEY"),
        ({"MFA_ENCRYPTION_KEY": ""}, "MFA_ENCRYPTION_KEY"),
    ],
)
def test_production_settings_refuse_weak_secrets(monkeypatch, env, match):
    import rideflow.settings as base

    good = {
        "DJANGO_DEBUG": "0",
        "DJANGO_SECRET_KEY": "p3-" + "x9Kq2LmZ" * 8,
        "MFA_ENCRYPTION_KEY": "a" * 43 + "=",
        "OTP_PROVIDER": "none",
        "DEV_ADMIN_MFA_BYPASS": "0",
        "RIDEFLOW_ENV": "production",
    }
    for k, v in {**good, **env}.items():
        monkeypatch.setenv(k, v)
    try:
        with pytest.raises(RuntimeError, match=match):
            importlib.reload(base)
        for k, v in good.items():
            monkeypatch.setenv(k, v)
        importlib.reload(base)
        assert base.SECURE_HSTS_SECONDS >= 31536000 and base.SESSION_COOKIE_SECURE and not base.API_DOCS_ENABLED
    finally:
        monkeypatch.undo()
        importlib.reload(base)


@pytest.fixture
def tight_throttles(monkeypatch):
    from django.core.cache import cache
    from rest_framework.throttling import SimpleRateThrottle

    rates = {
        **SimpleRateThrottle.THROTTLE_RATES,
        "platform_login": "3/hour",
        "platform_login_ip": "5/hour",
        "otp_request_ip": "3/hour",
    }
    monkeypatch.setattr(SimpleRateThrottle, "THROTTLE_RATES", rates)
    cache.clear()
    yield
    cache.clear()


def test_spoofed_forwarded_for_cannot_evade_ip_throttles(ta, tight_throttles):
    """Defect P3-01: rotating X-Forwarded-For gave every request a fresh per-IP throttle bucket."""
    client = APIClient()
    codes = [
        client.post(
            "/api/v1/auth/otp/request",
            {"phone": f"+96777100{i:04d}"},
            format="json",
            HTTP_X_RIDEFLOW_APP=ta.apps["rider"].client_id,
            HTTP_X_FORWARDED_FOR=f"10.66.{i}.1",
        ).status_code
        for i in range(5)
    ]
    assert codes[:3] != [429] * 3 and codes[3:] == [429, 429], codes


def test_platform_login_is_throttled_per_account_across_ips(tight_throttles):
    """Defect P3-01: platform password login had only a (spoofable) per-IP limit."""
    codes = [
        APIClient()
        .post(
            "/api/v1/auth/platform/login", {"phone": "+967700009999", "password": "wrong"}, format="json", REMOTE_ADDR=f"10.77.{i}.1"
        )
        .status_code
        for i in range(5)
    ]
    assert codes[:3] == [401, 401, 401] and codes[3:] == [429, 429], codes


def test_admin_list_endpoints_have_no_n_plus_one(ta, tb):
    """Phase 3 (E): query count of every tenant admin list must not grow with the number of rows."""
    from django.db import connection
    from django.test.utils import CaptureQueriesContext

    from .factories import make_driver, ride_payload
    from .scenario import populate

    populate(ta)
    populate(tb)
    for i in range(10):  # tenant B: ~10 more drivers, riders, open rides, memberships and audit rows
        rider = make_member(tb, "rider", name=f"Extra Rider {i}")
        make_driver(tb, offset=(0.001 * (i + 2), 0.001))
        api_for(tb, rider).post("/api/v1/rides", ride_payload(tb, dx=0.0005 * i))
    lists = [name for name, params in api_routes() if not params and name.startswith("admin-") and name.endswith("-list")]
    assert len(lists) >= 15, lists
    grew = {}
    for name in lists:
        url = reverse(name)
        counts = []
        for t in (ta, tb):
            api = api_for(t, make_member(t, "owner"))
            with CaptureQueriesContext(connection) as q:
                r = api.get(url, {"page_size": 50})
            assert r.status_code == 200, (name, r.status_code)
            counts.append(len(q))
        if counts[1] > counts[0] + 2:
            grew[name] = counts
    assert not grew, f"query count grows with rows (N+1): {grew}"


def test_redis_outage_returns_503_with_retry_after(ta, monkeypatch):
    """Defect P3-04: a cache (Redis) outage surfaced as an opaque 500 instead of a retryable 503."""
    from redis.exceptions import ConnectionError as RedisConnectionError
    from rest_framework.throttling import SimpleRateThrottle

    def down(*args, **kwargs):
        raise RedisConnectionError("Error 111 connecting to redis:6379. Connection refused.")

    monkeypatch.setattr(SimpleRateThrottle, "allow_request", down)
    r = APIClient().post(
        "/api/v1/auth/otp/request", {"phone": "+967788000003"}, format="json", HTTP_X_RIDEFLOW_APP=ta.apps["rider"].client_id
    )
    assert r.status_code == 503 and r.data["code"] == "service_unavailable" and r["Retry-After"] == "5"
    assert "redis" not in r.content.decode().lower()  # no infrastructure details leaked
