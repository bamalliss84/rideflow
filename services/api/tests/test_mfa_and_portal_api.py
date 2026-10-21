"""Administrator MFA and the backend additions made for the Phase 2 admin portal."""

import pytest
from rest_framework.test import APIClient

from apps.accounts import mfa
from apps.accounts.models import MFADevice
from apps.core.context import tenant_context
from apps.notifications.models import Notification

from .factories import Api, add_roles, api_for, make_driver, make_member, make_tenant, make_user

pytestmark = pytest.mark.django_db


def _first_factor(t, user):
    client = APIClient()
    app = t.apps["admin"].client_id
    client.post("/api/v1/auth/otp/request", {"phone": user.phone}, format="json", HTTP_X_RIDEFLOW_APP=app)
    r = client.post("/api/v1/auth/otp/verify", {"phone": user.phone, "code": "123456"}, format="json", HTTP_X_RIDEFLOW_APP=app)
    assert r.status_code == 200 and r.data["mfa_required"] is True, r.data
    return client, r.data


def _code(secret, offset=0):
    return mfa.totp(secret, mfa.current_step() + offset)


def test_tenant_admin_enrolment_and_login(ta):
    owner = make_member(ta, "owner")
    client, challenge = _first_factor(ta, owner)
    assert challenge["mfa_enrolled"] is False
    r = client.post("/api/v1/auth/mfa/setup", {"mfa_token": challenge["mfa_token"]}, format="json")
    assert r.status_code == 200 and r.data["otpauth_uri"].startswith("otpauth://totp/RideFlow")
    secret = r.data["secret"]
    with pytest.raises(AssertionError):
        assert MFADevice.objects.get(user=owner).secret_encrypted == secret  # stored encrypted, not in clear
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "code": "000000"}, format="json")
    assert r.status_code == 400 and r.data["code"] == "mfa_invalid"
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "code": _code(secret)}, format="json")
    assert r.status_code == 200 and r.data["scope"] == "tenant" and "access" in r.data
    session = APIClient()
    session.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
    me = session.get("/api/v1/me").data
    assert me["mfa"] == {"enrolled": True, "session_verified": True}
    assert session.get("/api/v1/admin/drivers").status_code == 200

    # second sign-in: already enrolled, setup refused, the same code cannot be replayed
    client, challenge = _first_factor(ta, owner)
    assert challenge["mfa_enrolled"] is True
    assert client.post("/api/v1/auth/mfa/setup", {"mfa_token": challenge["mfa_token"]}, format="json").status_code == 409
    replay = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "code": _code(secret)}, format="json")
    assert replay.status_code == 400
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "code": _code(secret, 1)}, format="json")
    assert r.status_code == 200


def test_challenge_tampering_and_attempt_limit(ta):
    owner = make_member(ta, "owner")
    client, challenge = _first_factor(ta, owner)
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"] + "x", "code": "123456"}, format="json")
    assert r.status_code == 401 and r.data["code"] == "mfa_challenge_invalid"
    client.post("/api/v1/auth/mfa/setup", {"mfa_token": challenge["mfa_token"]}, format="json")
    codes = [
        client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "code": "000001"}, format="json").status_code
        for _ in range(6)
    ]
    assert codes[:5] == [400] * 5 and codes[5] == 429


def test_staff_roles_require_mfa_claim(ta):
    owner = make_member(ta, "owner")
    assert Api(owner, tenant=ta.tenant, mfa=False).get("/api/v1/me").status_code == 401
    both = make_member(ta, "rider", "owner")
    api = Api(both, tenant=ta.tenant, mfa=False)  # e.g. a rider-app token of a staff member
    me = api.get("/api/v1/me").data
    assert me["tenant"]["roles"] == ["rider"] and me["permissions"] == []
    assert api.get("/api/v1/admin/drivers").status_code == 403


def test_platform_scope_requires_mfa(db):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.save()
    assert Api(admin, platform=True, mfa=False).get("/api/v1/platform/tenants").status_code == 401
    assert Api(admin, platform=True).get("/api/v1/platform/tenants").status_code == 200


def test_platform_password_login_then_mfa(db):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.set_password("a-strong-password-1")
    admin.save()
    client = APIClient()
    r = client.post("/api/v1/auth/platform/login", {"phone": admin.phone, "password": "a-strong-password-1"}, format="json")
    token = r.data["mfa_token"]
    secret = client.post("/api/v1/auth/mfa/setup", {"mfa_token": token}, format="json").data["secret"]
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": token, "code": _code(secret)}, format="json")
    assert r.status_code == 200 and r.data["scope"] == "platform" and r.data["tenant"] is None


def test_app_context_is_public_and_minimal(ta):
    r = APIClient().get("/api/v1/auth/app-context", HTTP_X_RIDEFLOW_APP=ta.apps["admin"].client_id)
    assert r.status_code == 200 and set(r.data) == {"tenant_name", "app_type", "locale", "tenant_status"}


def test_member_mfa_reset_rules(ta, tb):
    owner = make_member(ta, "owner")
    reviewer = make_member(ta, "reviewer")
    MFADevice.objects.create(user=reviewer, secret_encrypted=mfa.encrypt_secret(mfa.new_secret()))
    api = api_for(ta, owner)
    with tenant_context(ta.tenant):
        own = owner.memberships.get(role="owner")
        rev = reviewer.memberships.get(role="reviewer")
    assert api.post(f"/api/v1/admin/members/{own.pk}/reset-mfa").status_code == 422
    assert api.post(f"/api/v1/admin/members/{rev.pk}/reset-mfa").status_code == 200
    assert not MFADevice.objects.filter(user=reviewer).exists()
    shared = make_member(ta, "admin")
    add_roles(tb, shared, "admin")
    with tenant_context(ta.tenant):
        shared_m = shared.memberships.get(role="admin")
    r = api.post(f"/api/v1/admin/members/{shared_m.pk}/reset-mfa")
    assert r.status_code == 422 and r.data["code"] == "cross_tenant_user"


def test_platform_overview_audit_and_admins(ta):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.save()
    platform = Api(admin, platform=True)
    make_member(ta, "owner")
    make_driver(ta)
    overview = platform.get("/api/v1/platform/overview").data
    row = next(r for r in overview["per_tenant"] if r["slug"] == "alpha")
    assert row["drivers"] == 1 and row["staff"] == 1 and overview["tenants"]["total"] >= 1
    admins = platform.get(f"/api/v1/platform/tenants/{ta.tenant.pk}/admins").data
    assert len(admins) == 1 and admins[0]["role"] == "owner" and admins[0]["mfa_enrolled"] is False
    platform.post(f"/api/v1/platform/tenants/{ta.tenant.pk}/suspend")
    events = platform.get("/api/v1/platform/audit-events").data["results"]
    assert events and all(e["action"].startswith("platform.") for e in events)
    # tenant staff cannot reach platform APIs
    assert api_for(ta, make_member(ta, "owner")).get("/api/v1/platform/overview").status_code == 403


def test_riders_ratings_and_staff_notifications(ride_flow):
    f = ride_flow
    ride = f.completed()
    f.d1_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 4})
    owner_api = api_for(f.tenant, make_member(f.tenant, "owner"))
    riders = owner_api.get("/api/v1/admin/riders", {"q": f.rider_user.phone[-6:]}).data["results"]
    assert len(riders) == 1 and riders[0]["rides_total"] == 1 and riders[0]["rides_completed"] == 1
    detail = owner_api.get(f"/api/v1/admin/riders/{riders[0]['id']}").data
    assert detail["recent_rides"][0]["rider_name"] == f.rider_user.full_name
    ratings = owner_api.get("/api/v1/admin/ratings").data["results"]
    assert ratings[0]["ratee_name"] == f.rider_user.full_name
    rides = owner_api.get("/api/v1/admin/rides").data["results"]
    assert rides[0]["city_name"] and rides[0]["driver_name"]
    dash = owner_api.get("/api/v1/admin/dashboard").data
    assert set(dash["live"]) == {"requests_open", "awaiting_driver_confirmation", "on_trip", "open_bids"}
    # staff notification when a dispute is opened
    reviewer = make_member(f.tenant, "reviewer")
    f.rider_api.post(f"/api/v1/rides/{ride['id']}/disputes", {"category": "fare", "description": "x"})
    with tenant_context(f.tenant.tenant):
        assert Notification.objects.filter(user=reviewer, kind="staff.dispute_opened").exists()


def test_new_tenant_has_no_cross_tenant_riders(ta, tb):
    make_member(ta, "rider")
    assert api_for(tb, make_member(tb, "owner")).get("/api/v1/admin/riders").data["count"] == 0
    assert make_tenant  # factories import used
