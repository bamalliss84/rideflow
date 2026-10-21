import pytest
from rest_framework.test import APIClient

from apps.core.context import tenant_context
from apps.core.models import AuditEvent
from apps.rides.models import Ride
from apps.tenancy.models import Tenant

from .factories import Api, api_for, make_member, make_user, ride_payload

pytestmark = pytest.mark.django_db


@pytest.fixture
def platform_api(db):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.save()
    return Api(admin, platform=True)


def test_platform_provisions_tenant_with_apps_and_first_admin(platform_api):
    r = platform_api.post(
        "/api/v1/platform/tenants", {"name": "Seiyun Rides", "slug": "seiyun", "currency": "yer", "time_zone": "Asia/Aden"}
    )
    assert r.status_code == 201, r.data
    assert r.data["currency"] == "YER"
    tenant_id = r.data["id"]
    apps = platform_api.get(f"/api/v1/platform/tenants/{tenant_id}/applications").data
    assert {a["app_type"] for a in apps} == {"rider", "driver", "admin"}
    r = platform_api.post(f"/api/v1/platform/tenants/{tenant_id}/admins", {"phone": "+967733000001"})
    assert r.status_code == 201 and r.data["role"] == "owner"
    admin_app = next(a for a in apps if a["app_type"] == "admin")
    client = APIClient()
    client.post("/api/v1/auth/otp/request", {"phone": "+967733000001"}, format="json", HTTP_X_RIDEFLOW_APP=admin_app["client_id"])
    r = client.post(
        "/api/v1/auth/otp/verify",
        {"phone": "+967733000001", "code": "123456"},
        format="json",
        HTTP_X_RIDEFLOW_APP=admin_app["client_id"],
    )
    assert r.status_code == 200 and r.data["mfa_required"] is True and r.data["tenant"]["roles"] == ["owner"]
    assert AuditEvent.objects.filter(action="platform.tenant_created", actor=platform_api.user).exists()


def test_platform_rejects_invalid_tenant_and_currency_change(platform_api, ta):
    r = platform_api.post("/api/v1/platform/tenants", {"name": "X", "slug": "x", "currency": "YE", "time_zone": "Mars/Base"})
    assert r.status_code == 400
    r = platform_api.patch(f"/api/v1/platform/tenants/{ta.tenant.pk}", {"currency": "USD"})
    assert r.status_code == 400


def test_tenant_users_cannot_use_platform_api(ta):
    owner = make_member(ta, "owner")
    assert api_for(ta, owner).get("/api/v1/platform/tenants").status_code == 403


def test_suspended_tenant_blocks_new_rides_but_active_trips_finish(platform_api, ride_flow):
    f = ride_flow
    ride = f.assigned()
    platform_api.post(f"/api/v1/platform/tenants/{f.tenant.tenant.pk}/suspend")
    assert Tenant.objects.get(pk=f.tenant.tenant.pk).status == "suspended"
    other = api_for(f.tenant, make_member(f.tenant, "rider"))
    r = other.post("/api/v1/rides", ride_payload(f.tenant))
    assert r.status_code == 403 and r.data["code"] == "tenant_suspended"
    r = f.d1_api.post(f"/api/v1/rides/{ride['id']}/en-route", {"expected_version": ride["version"]})
    assert r.status_code == 200  # OD-08: active trips finish


def test_role_permissions_matrix(ta):
    roles = {r: api_for(ta, make_member(ta, r)) for r in ("owner", "admin", "reviewer", "finance", "support")}
    rider = api_for(ta, make_member(ta, "rider"))
    expectations = {
        "/api/v1/admin/members": {"owner", "admin"},
        "/api/v1/admin/drivers": {"owner", "admin", "reviewer", "finance", "support"},
        "/api/v1/admin/deposit-claims": {"owner", "admin", "finance", "support"},
        "/api/v1/admin/violations": {"owner", "admin", "reviewer"},
        "/api/v1/admin/disputes": {"owner", "admin", "reviewer"},
        "/api/v1/admin/audit-events": {"owner", "admin"},
        "/api/v1/admin/dashboard": {"owner", "admin", "reviewer", "finance"},
        "/api/v1/admin/rides": {"owner", "admin", "reviewer", "support"},
    }
    for url, allowed in expectations.items():
        for role, api in roles.items():
            status = api.get(url).status_code
            assert (status == 200) == (role in allowed), (url, role, status)
        assert rider.get(url).status_code == 403, url


def test_member_management_rules(ta):
    owner = make_member(ta, "owner")
    admin = make_member(ta, "admin")
    owner_api, admin_api = api_for(ta, owner), api_for(ta, admin)
    r = admin_api.post("/api/v1/admin/members", {"phone": "+967744000001", "role": "owner"})
    assert r.status_code == 422 and r.data["code"] == "owner_required"
    r = admin_api.post("/api/v1/admin/members", {"phone": "+967744000001", "role": "reviewer"})
    assert r.status_code == 201
    with tenant_context(ta.tenant):
        own = owner.memberships.get(role="owner")
    assert admin_api.post(f"/api/v1/admin/members/{own.pk}/suspend").status_code == 422
    r = owner_api.post(f"/api/v1/admin/members/{r.data['id']}/suspend")
    assert r.status_code == 200 and r.data["status"] == "suspended"


def test_config_versioning_validation_and_ride_snapshot(ride_flow):
    f = ride_flow
    owner_api = api_for(f.tenant, make_member(f.tenant, "owner"))
    r = owner_api.post("/api/v1/admin/config", {"params": {"unknown.key": 1, "bids.expiry_seconds": 1}})
    assert r.status_code == 400
    assert set(r.data["errors"]["params"]) == {"unknown.key", "bids.expiry_seconds"}
    r = owner_api.post("/api/v1/admin/config", {"params": {"trust.tier_thresholds": {"silver": 90, "gold": 10, "diamond": 95}}})
    assert r.status_code == 400
    r = owner_api.post("/api/v1/admin/config", {"params": {"bids.expiry_seconds": 300}, "note": "longer bids"})
    assert r.status_code == 201 and r.data["version"] == 1
    r = owner_api.post("/api/v1/admin/config", {"params": {"dispatch.wave_size": 5}})
    assert r.data["version"] == 2 and r.data["params"] == {"bids.expiry_seconds": 300, "dispatch.wave_size": 5}
    config = owner_api.get("/api/v1/admin/config").data
    assert config["effective"]["dispatch.wave_size"] == 5
    assert any(p["key"] == "noshow.geofence_m" and p["status"] == "PROPOSED" for p in config["parameters"])
    ride = f.create()
    assert ride["config_version"] == 2
    assert len(owner_api.get("/api/v1/admin/config/versions").data["results"]) == 2


def test_dashboard_reports_and_audit(ride_flow):
    f = ride_flow
    f.completed()
    owner_api = api_for(f.tenant, make_member(f.tenant, "owner"))
    dash = owner_api.get("/api/v1/admin/dashboard").data
    assert dash["rides"]["requested"] == 1 and dash["rides"]["completed"] == 1
    assert dash["rates"]["completion_rate"] == 1.0 and dash["rates"]["bid_coverage"] == 1.0
    assert dash["drivers"]["approved"] == 2 and dash["currency"] == "YER"
    assert dash["timing_seconds"]["median_time_to_first_bid"] is not None
    daily = owner_api.get("/api/v1/admin/reports/rides-daily").data
    assert sum(row["completed"] for row in daily["rows"]) == 1
    assert owner_api.get("/api/v1/admin/reports/subscriptions").status_code == 200
    r = owner_api.get("/api/v1/admin/reports/rides-daily", {"date_from": "2026-01-01T00:00:00Z", "date_to": "2025-01-01T00:00:00Z"})
    assert r.status_code == 422
    audit = owner_api.get("/api/v1/admin/audit-events", {"action": "ride."}).data["results"]
    assert {"ride.requested", "ride.bid_selected", "ride.match_confirmed"} <= {a["action"] for a in audit}


def test_admin_ride_explorer_filters(ride_flow):
    f = ride_flow
    ride = f.create()
    support_api = api_for(f.tenant, make_member(f.tenant, "support"))
    rows = support_api.get("/api/v1/admin/rides", {"status": "bidding"}).data["results"]
    assert [r["id"] for r in rows] == [ride["id"]]
    assert support_api.get("/api/v1/admin/rides", {"status": "completed"}).data["count"] == 0
    assert support_api.get("/api/v1/admin/rides", {"rider": str(f.rider_user.pk)}).data["count"] == 1
    events = support_api.get(f"/api/v1/admin/rides/{ride['id']}/events").data
    assert events[0]["event_type"] == "requested"


def test_filter_by_other_tenant_id_returns_nothing(ride_flow, tb):
    f = ride_flow
    f.create()
    with tenant_context(f.tenant.tenant):
        ride = Ride.objects.get()
    attacker = api_for(tb, make_member(tb, "owner"))
    assert attacker.get("/api/v1/admin/rides", {"rider": str(ride.rider_id)}).data["count"] == 0
    assert attacker.get("/api/v1/admin/violations", {"ride": str(ride.pk)}).data["count"] == 0
