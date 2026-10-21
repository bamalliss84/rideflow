import pytest
from rest_framework.test import APIClient

from apps.accounts.models import PhoneOTP, User
from apps.core.context import tenant_context
from apps.drivers.models import DriverProfile
from apps.tenancy.models import TenantMembership

from .factories import Api, api_for, make_member, make_user

pytestmark = pytest.mark.django_db


def _otp(client, app, phone, code="123456"):
    r = client.post("/api/v1/auth/otp/request", {"phone": phone}, format="json", HTTP_X_RIDEFLOW_APP=app.client_id)
    assert r.status_code == 202, r.data
    return client.post("/api/v1/auth/otp/verify", {"phone": phone, "code": code}, format="json", HTTP_X_RIDEFLOW_APP=app.client_id)


def test_otp_requires_application_context(ta):
    r = APIClient().post("/api/v1/auth/otp/request", {"phone": "+967700000999"}, format="json")
    assert r.status_code == 400 and r.data["code"] == "app_required"
    r = APIClient().post("/api/v1/auth/otp/request", {"phone": "+967700000999"}, format="json", HTTP_X_RIDEFLOW_APP="unknown")
    assert r.status_code == 400 and r.data["code"] == "app_invalid"


def test_rider_login_creates_global_user_and_tenant_membership(ta):
    r = _otp(APIClient(), ta.apps["rider"], "+967700000123")
    assert r.status_code == 200, r.data
    assert r.data["is_new_user"] is True
    assert r.data["tenant"]["roles"] == ["rider"]
    access = r.data["access"]
    me = APIClient()
    me.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    body = me.get("/api/v1/me").data
    assert str(body["tenant"]["tenant_id"]) == str(ta.tenant.pk)
    assert body["currency"] == "YER"
    with tenant_context(ta.tenant):
        assert PhoneOTP.objects.get().consumed_at is not None
        # only an HMAC of the code is stored
        assert "123456" not in PhoneOTP.objects.get().code_hash


def test_same_phone_in_two_tenants_is_one_identity_with_two_memberships(ta, tb):
    _otp(APIClient(), ta.apps["rider"], "+967700000124")
    r = _otp(APIClient(), tb.apps["rider"], "+967700000124")
    assert r.data["is_new_user"] is False
    user = User.objects.get(phone="+967700000124")
    assert TenantMembership.all_tenants.filter(user=user).count() == 2


def test_driver_app_login_creates_driver_profile(ta):
    r = _otp(APIClient(), ta.apps["driver"], "+967700000125")
    assert r.data["tenant"]["roles"] == ["driver"]
    with tenant_context(ta.tenant):
        assert DriverProfile.objects.filter(user__phone="+967700000125", status="pending_documents").exists()


def test_admin_app_requires_existing_staff_membership(ta):
    r = _otp(APIClient(), ta.apps["admin"], "+967700000126")
    assert r.status_code == 403
    staff = make_member(ta, "finance")
    r = _otp(APIClient(), ta.apps["admin"], staff.phone)
    # staff never get tokens from the first factor alone: an MFA challenge is returned instead
    assert r.status_code == 200 and r.data["mfa_required"] is True and "access" not in r.data
    assert r.data["tenant"]["roles"] == ["finance"]


def test_wrong_code_counts_attempts_and_locks(ta, settings):
    settings.OTP_MAX_ATTEMPTS = 2
    client = APIClient()
    phone = "+967700000127"
    client.post("/api/v1/auth/otp/request", {"phone": phone}, format="json", HTTP_X_RIDEFLOW_APP=ta.apps["rider"].client_id)
    for _ in range(2):
        r = client.post(
            "/api/v1/auth/otp/verify",
            {"phone": phone, "code": "000000"},
            format="json",
            HTTP_X_RIDEFLOW_APP=ta.apps["rider"].client_id,
        )
        assert r.status_code == 400 and r.data["code"] == "otp_invalid"
    r = client.post(
        "/api/v1/auth/otp/verify", {"phone": phone, "code": "123456"}, format="json", HTTP_X_RIDEFLOW_APP=ta.apps["rider"].client_id
    )
    assert r.status_code == 429


def test_otp_request_is_throttled_per_phone(ta, monkeypatch):
    from django.core.cache import cache
    from rest_framework.throttling import SimpleRateThrottle

    cache.clear()
    monkeypatch.setattr(SimpleRateThrottle, "THROTTLE_RATES", {**SimpleRateThrottle.THROTTLE_RATES, "otp_request": "2/hour"})
    client = APIClient()
    codes = [
        client.post(
            "/api/v1/auth/otp/request", {"phone": "+967700000128"}, format="json", HTTP_X_RIDEFLOW_APP=ta.apps["rider"].client_id
        ).status_code
        for _ in range(3)
    ]
    assert codes == [202, 202, 429]


def test_suspended_membership_is_rejected_immediately(ta):
    rider = make_member(ta, "rider")
    api = api_for(ta, rider)
    assert api.get("/api/v1/me").status_code == 200
    with tenant_context(ta.tenant):
        TenantMembership.objects.filter(user=rider).update(status="suspended")
    assert api.get("/api/v1/me").status_code == 401


def test_logout_blacklists_refresh_token(ta):
    rider = make_member(ta, "rider")
    api = api_for(ta, rider)
    refresh = api.tokens["refresh"]
    assert api.post("/api/v1/auth/logout", {"refresh": refresh}).status_code == 205
    r = APIClient().post("/api/v1/auth/token/refresh", {"refresh": refresh}, format="json")
    assert r.status_code == 401


def test_refresh_keeps_tenant_claim(ta):
    rider = make_member(ta, "rider")
    refresh = api_for(ta, rider).tokens["refresh"]
    r = APIClient().post("/api/v1/auth/token/refresh", {"refresh": refresh}, format="json")
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
    assert str(client.get("/api/v1/me").data["tenant"]["tenant_id"]) == str(ta.tenant.pk)


def test_platform_login(db):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.set_password("a-strong-password-1")
    admin.save()
    r = APIClient().post("/api/v1/auth/platform/login", {"phone": admin.phone, "password": "wrong"}, format="json")
    assert r.status_code == 401
    r = APIClient().post("/api/v1/auth/platform/login", {"phone": admin.phone, "password": "a-strong-password-1"}, format="json")
    assert r.status_code == 200 and r.data["mfa_required"] is True and "access" not in r.data


def test_unauthenticated_requests_are_rejected(ta):
    assert APIClient().get("/api/v1/me").status_code == 401
    assert APIClient().get("/api/v1/rides").status_code == 401


def test_platform_token_cannot_use_tenant_endpoints(ta):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.save()
    api = Api(admin, platform=True)
    assert api.get("/api/v1/rides").status_code == 403
    assert api.get("/api/v1/admin/drivers").status_code == 403
