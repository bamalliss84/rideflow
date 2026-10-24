"""Administrator MFA recovery codes (Phase 3, G): one-time, hashed, never bypass the first factor."""

import pytest
from rest_framework.test import APIClient

from apps.accounts import mfa
from apps.accounts.models import MFADevice, MFARecoveryCode
from apps.core.models import AuditEvent

from .factories import Api, make_member, make_user
from .test_mfa_and_portal_api import _code, _first_factor

pytestmark = pytest.mark.django_db


def _enrol(user):
    secret = mfa.new_secret()
    MFADevice.objects.create(user=user, secret_encrypted=mfa.encrypt_secret(secret), confirmed_at="2026-10-01T00:00:00Z")
    return secret


def _generate(api, secret, offset=0):
    return api.post("/api/v1/auth/mfa/recovery-codes", {"code": _code(secret, offset)})


def test_generation_requires_real_mfa_session_and_fresh_authenticator_code(ta):
    owner = make_member(ta, "owner")
    secret = _enrol(owner)
    verified = Api(owner, tenant=ta.tenant)
    # not enrolled user / dev-bypass style session without the `mfa` claim
    other = make_member(ta, "owner")
    assert Api(other, tenant=ta.tenant).get("/api/v1/auth/mfa/recovery-codes").status_code == 403
    assert verified.post("/api/v1/auth/mfa/recovery-codes", {"code": "000000"}).status_code == 400
    r = _generate(verified, secret)
    assert r.status_code == 201 and len(r.data["codes"]) == 10 and r.data["remaining"] == 10
    assert len(set(r.data["codes"])) == 10
    stored = list(MFARecoveryCode.objects.filter(user=owner).values_list("code_hash", flat=True))
    assert not any(c.replace("-", "") in h or c in h for c in r.data["codes"] for h in stored)  # only keyed hashes
    # the same authenticator code cannot be replayed to regenerate again
    assert _generate(verified, secret).status_code == 400
    assert AuditEvent.objects.filter(action="auth.mfa_recovery_codes_generated", actor=owner).count() == 1
    assert "codes" not in verified.get("/api/v1/auth/mfa/recovery-codes").data


def test_recovery_code_signs_in_once_only_after_first_factor(ta):
    owner = make_member(ta, "owner")
    secret = _enrol(owner)
    codes = _generate(Api(owner, tenant=ta.tenant), secret).data["codes"]
    client, challenge = _first_factor(ta, owner)
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "recovery_code": codes[0].upper()}, format="json")
    assert r.status_code == 200 and r.data["scope"] == "tenant"
    session = APIClient()
    session.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
    assert session.get("/api/v1/me").data["mfa"]["recovery_codes_remaining"] == 9
    event = AuditEvent.objects.filter(action="auth.login", actor=owner).latest("created_at")
    assert event.data["recovery_code"] is True and event.data["recovery_codes_remaining"] == 9
    # reuse is refused, even on a new challenge
    client, challenge = _first_factor(ta, owner)
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "recovery_code": codes[0]}, format="json")
    assert r.status_code == 400 and r.data["code"] == "mfa_invalid"
    # no challenge (no first factor) -> nothing to redeem against
    r = APIClient().post("/api/v1/auth/mfa/verify", {"mfa_token": "forged", "recovery_code": codes[1]}, format="json")
    assert r.status_code in (400, 401)
    assert MFARecoveryCode.objects.filter(user=owner, used_at__isnull=True).count() == 9
    # exactly one of code / recovery_code
    r = client.post(
        "/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "code": "123456", "recovery_code": codes[1]}, format="json"
    )
    assert r.status_code == 400


def test_regeneration_invalidates_previous_codes(ta):
    owner = make_member(ta, "owner")
    secret = _enrol(owner)
    api = Api(owner, tenant=ta.tenant)
    old = _generate(api, secret).data["codes"]
    new = _generate(api, secret, offset=1).data["codes"]
    assert not set(old) & set(new)
    client, challenge = _first_factor(ta, owner)
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "recovery_code": old[0]}, format="json")
    assert r.status_code == 400
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "recovery_code": new[0]}, format="json")
    assert r.status_code == 200


def test_recovery_brute_force_is_bounded_by_challenge_attempt_limit(ta):
    owner = make_member(ta, "owner")
    secret = _enrol(owner)
    codes = _generate(Api(owner, tenant=ta.tenant), secret).data["codes"]
    client, challenge = _first_factor(ta, owner)
    statuses = [
        client.post(
            "/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "recovery_code": f"{i:05x}-00000"}, format="json"
        ).status_code
        for i in range(5)
    ]
    assert statuses == [400] * 5
    # the 6th attempt is refused even with a valid code, and the valid code is not consumed
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": challenge["mfa_token"], "recovery_code": codes[0]}, format="json")
    assert r.status_code == 429
    assert MFARecoveryCode.objects.filter(user=owner, used_at__isnull=True).count() == 10


def test_codes_are_bound_to_their_user_and_work_for_platform_scope(ta):
    owner = make_member(ta, "owner")
    owner_codes = _generate(Api(owner, tenant=ta.tenant), _enrol(owner)).data["codes"]
    admin = make_user("Platform Admin")
    admin.is_platform_admin = True
    admin.set_password("Pl@tform-pass-123")
    admin.save()
    secret = _enrol(admin)
    platform_codes = _generate(Api(admin, platform=True), secret).data["codes"]
    login = APIClient().post("/api/v1/auth/platform/login", {"phone": admin.phone, "password": "Pl@tform-pass-123"}, format="json")
    token = login.data["mfa_token"]
    client = APIClient()
    # another user's valid code does not work for this account
    assert (
        client.post("/api/v1/auth/mfa/verify", {"mfa_token": token, "recovery_code": owner_codes[0]}, format="json").status_code == 400
    )
    r = client.post("/api/v1/auth/mfa/verify", {"mfa_token": token, "recovery_code": platform_codes[0]}, format="json")
    assert r.status_code == 200 and r.data["scope"] == "platform"
    # the first factor is still mandatory: wrong password yields no challenge at all
    bad = APIClient().post("/api/v1/auth/platform/login", {"phone": admin.phone, "password": "wrong"}, format="json")
    assert bad.status_code == 401 and "mfa_token" not in bad.data
