"""Mandatory tenant isolation suite (TEST_PLAN §3, D017)."""

import json

import pytest
from django.db import DatabaseError, IntegrityError, connection, transaction
from django.urls import URLPattern, URLResolver, get_resolver, reverse

from apps.core.context import TenantContextMissing, set_locked, system_context, tenant_context
from apps.rides.models import Bid, Ride

from .factories import Api, add_roles, api_for, make_driver, make_member, ride_payload
from .scenario import populate

pytestmark = pytest.mark.django_db

PUBLIC_ROUTES = {"otp-request", "otp-verify", "platform-login", "token-refresh", "app-context", "mfa-setup", "mfa-verify"}


def _walk(patterns, out):
    for p in patterns:
        if isinstance(p, URLResolver):
            _walk(p.url_patterns, out)
        elif isinstance(p, URLPattern) and p.name:
            out.append((p.name, list(p.pattern.regex.groupindex)))
    return out


def api_routes():
    routes = []
    for name, params in _walk(get_resolver().url_patterns, []):
        kwargs = {p: "00000000-0000-0000-0000-000000000000" for p in params}
        try:
            url = reverse(name, kwargs=kwargs)
        except Exception:
            continue
        if url.startswith("/api/v1/"):
            routes.append((name, params))
    return sorted(set((n, tuple(p)) for n, p in routes))


OBJECT_FOR_PREFIX = [
    # (route-name prefix, object attribute) - the longest matching prefix wins
    ("admin-driver-document", "document"),
    ("driver-document", "document"),
    ("admin-driver", "driver"),
    ("admin-vehicle", "vehicle"),
    ("driver-vehicle", "vehicle"),
    ("admin-ride", "ride"),
    ("ride", "ride"),
    ("admin-city", "city"),
    ("admin-service-area", "area"),
    ("driver-deposit-claim", "claim"),
    ("admin-deposit-claim", "claim"),
    ("admin-plan", "plan"),
    ("admin-deposit-account", "account"),
    ("admin-subscription", "subscription"),
    ("admin-ledger", "ledger"),
    ("my-violation", "violation"),
    ("admin-violation", "violation"),
    ("admin-enforcement", "enforcement"),
    ("admin-appeal", "appeal"),
    ("my-dispute", "dispute"),
    ("admin-dispute", "dispute"),
    ("admin-trust-snapshot", "snapshot"),
    ("admin-member", "membership"),
    ("admin-config-version", "config"),
    ("admin-audit", "audit"),
    ("admin-rider", "rider_membership"),
    ("admin-rating", "rating"),
    ("platform-audit", "audit"),
    ("platform-tenant", "tenant"),
]
PARAM_OBJECTS = {"ride_id": "ride", "bid_id": "bid", "amendment_id": "amendment", "membership_id": "membership"}


def _object_for(name, param, objects, tenant):
    if param in PARAM_OBJECTS:
        return getattr(objects, PARAM_OBJECTS[param])
    for prefix, attr in sorted(OBJECT_FOR_PREFIX, key=lambda x: -len(x[0])):
        if name.startswith(prefix):
            return tenant if attr == "tenant" else getattr(objects, attr)
    return None


@pytest.fixture
def two_tenants(ta, tb):
    a = populate(ta)
    b = populate(tb)
    attacker = make_member(tb, "owner", "rider", name="Attacker")
    make_driver(tb, user=attacker)
    return a, b, api_for(tb, attacker)


def _a_ids(a):
    ids = set()
    for value in vars(a.objects).values():
        if hasattr(value, "pk"):
            ids.add(str(value.pk))
    ids.add(str(a.rider.pk))
    ids.add(str(a.owner.pk))
    ids.add(a.rider.phone)
    return {i for i in ids if len(i) >= 12}  # UUIDs and phones; short integer ids would match by accident


def _fingerprint(t):
    with tenant_context(t.tenant):
        return json.dumps(
            sorted(
                [(str(r.pk), r.status, r.version) for r in Ride.objects.all()] + [(str(b.pk), b.status, 0) for b in Bid.objects.all()]
            )
        )


def test_every_tenant_route_is_classified_and_isolated(two_tenants):
    """Generated test: CI fails if a route has no isolation coverage (TEST_PLAN §3)."""
    a, _b, attacker = two_tenants
    leaked_ids = _a_ids(a)
    before = _fingerprint(a.t)
    unclassified = []
    checked = 0
    for name, params in api_routes():
        if name in PUBLIC_ROUTES:
            continue
        kwargs = {}
        for param in params:
            obj = _object_for(name, param, a.objects, a.t.tenant)
            if obj is None:
                unclassified.append(name)
                break
            kwargs[param] = str(obj.pk)
        else:
            url = reverse(name, kwargs=kwargs)
            checked += 1
            response = attacker.get(url)
            if response.status_code == 405:
                response = attacker.post(url, {})
                if params:  # acting on a tenant A object id must never find it
                    assert response.status_code in (400, 403, 404, 405), (name, url, response.status_code)
                else:  # the attacker's own tenant-B resources: any handled outcome, no leaks
                    assert response.status_code < 500, (name, url, response.status_code)
            elif params:
                assert response.status_code in (403, 404), (name, url, response.status_code)
            else:
                assert response.status_code in (200, 400, 403), (name, url, response.status_code)
            body = response.content.decode(errors="ignore") if hasattr(response, "content") else ""
            if response.get("Content-Type", "").startswith("application/json"):
                for leaked in leaked_ids:
                    assert leaked not in body, f"{name} leaked tenant A data {leaked}"
    assert not unclassified, f"routes without isolation coverage: {sorted(set(unclassified))}"
    assert checked >= 60, checked
    assert _fingerprint(a.t) == before


def test_forged_tenant_in_payload_is_ignored(ta, tb):
    rider = make_member(ta, "rider")
    make_driver(ta)
    body = {**ride_payload(ta), "tenant": str(tb.tenant.pk), "tenant_id": str(tb.tenant.pk)}
    r = api_for(ta, rider).post("/api/v1/rides", body)
    assert r.status_code == 201
    with system_context():
        assert Ride.all_tenants.get(pk=r.data["id"]).tenant_id == ta.tenant.pk


def test_app_header_of_other_tenant_is_rejected(ta, tb):
    rider = make_member(ta, "rider")
    api = api_for(ta, rider)
    assert api.get("/api/v1/me").status_code == 200
    r = api.get("/api/v1/me", HTTP_X_RIDEFLOW_APP=tb.apps["rider"].client_id)
    assert r.status_code == 401


def test_token_for_tenant_without_membership_is_rejected(ta, tb):
    rider = make_member(ta, "rider")
    r = Api(rider, tenant=tb.tenant).get("/api/v1/me")
    assert r.status_code == 401


def test_orm_fails_closed_without_tenant_context(ta):
    with pytest.raises(TenantContextMissing):
        list(Ride.objects.all())
    with pytest.raises(TenantContextMissing):
        Ride.objects.count()


def test_row_level_security_blocks_cross_tenant_rows(ta, tb):
    for t in (ta, tb):
        make_member(t, "rider")
        make_driver(t)
        rider = make_member(t, "rider")
        assert api_for(t, rider).post("/api/v1/rides", ride_payload(t)).status_code == 201

    def raw_count(sql="SELECT count(*) FROM rides_ride"):
        with connection.cursor() as cursor:
            cursor.execute(sql)
            return cursor.fetchone()[0]

    with system_context():
        assert raw_count() == 2
    with tenant_context(ta.tenant):
        assert raw_count() == 1  # raw SQL bypasses the ORM manager; RLS still filters
        assert raw_count(f"SELECT count(*) FROM rides_ride WHERE tenant_id = '{tb.tenant.pk}'") == 0
    set_locked()
    try:
        assert raw_count() == 0  # request without tenant: nothing visible
    finally:
        with system_context():
            pass


def test_row_level_security_blocks_cross_tenant_insert(ta, tb):
    make_driver(ta)
    rider = make_member(ta, "rider")
    ride_id = api_for(ta, rider).post("/api/v1/rides", ride_payload(ta)).data["id"]
    with tenant_context(tb.tenant), connection.cursor() as cursor:
        cursor.execute("UPDATE rides_ride SET status = 'cancelled' WHERE id = %s", [ride_id])
        assert cursor.rowcount == 0  # RLS hides tenant A's row from tenant B, even for raw SQL
        with pytest.raises(DatabaseError, match="row-level security"), transaction.atomic():
            cursor.execute(
                "INSERT INTO geo_city (id, tenant_id, name, slug, center, time_zone, is_active, created_at, updated_at) "
                "VALUES (gen_random_uuid(), %s, 'x', 'x', 'SRID=4326;POINT(0 0)', '', true, now(), now())",
                [str(ta.tenant.pk)],
            )
    with system_context():
        assert Ride.all_tenants.get(pk=ride_id).status == "bidding"


def test_composite_foreign_key_rejects_cross_tenant_relation(ta, tb):
    make_driver(ta)
    rider = make_member(ta, "rider")
    ride_id = api_for(ta, rider).post("/api/v1/rides", ride_payload(ta)).data["id"]
    driver_b = make_driver(tb)
    with system_context():
        ride = Ride.all_tenants.get(pk=ride_id)
        with pytest.raises(IntegrityError), transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute("SET CONSTRAINTS ALL IMMEDIATE")
            Bid.all_tenants.create(
                tenant=tb.tenant, ride=ride, driver=driver_b, amount_minor=1, currency="SAR", eta_seconds=1, expires_at=ride.created_at
            )


def test_orm_refuses_cross_tenant_write(ta, tb):
    from apps.core.context import CrossTenantWrite

    with tenant_context(ta.tenant):
        city = ta.city
    with tenant_context(tb.tenant), pytest.raises(CrossTenantWrite):
        city.name = "hijack"
        city.save()


def test_trust_and_config_never_cross_tenants(ta, tb):
    owner_a = make_member(ta, "owner")
    assert api_for(ta, owner_a).post("/api/v1/admin/config", {"params": {"bids.expiry_seconds": 999}}).status_code == 201
    owner_b = make_member(tb, "owner")
    config_b = api_for(tb, owner_b).get("/api/v1/admin/config").data
    assert config_b["version"] == 0
    assert config_b["effective"]["bids.expiry_seconds"] == 120
    # Same global user in both tenants has independent trust profiles
    shared = make_member(ta, "rider")
    add_roles(tb, shared, "rider")
    a = api_for(ta, shared).get("/api/v1/me/trust", {"role": "rider"}).data
    b = api_for(tb, shared).get("/api/v1/me/trust", {"role": "rider"}).data
    assert a["completed_rides"] == b["completed_rides"] == 0


def test_notifications_and_websocket_groups_are_tenant_namespaced(ta, tb):
    from apps.notifications.services import user_group

    user = make_member(ta, "rider")
    add_roles(tb, user, "rider")
    assert user_group(ta.tenant.pk, user.pk) != user_group(tb.tenant.pk, user.pk)


def test_uploaded_files_are_stored_under_tenant_namespace(ta):
    driver = make_driver(ta)
    with tenant_context(ta.tenant):
        doc = driver.documents.first()
        assert doc.file.name.startswith(f"tenants/{ta.tenant.pk}/")
