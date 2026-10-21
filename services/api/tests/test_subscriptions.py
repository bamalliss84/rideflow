import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.core.context import tenant_context
from apps.subscriptions.models import DriverSubscription, SubscriptionLedgerEntry
from apps.tenancy.services import create_config_version

from .factories import PDF, PNG, api_for, make_driver, make_member

pytestmark = pytest.mark.django_db


def _claim(api, t, reference="REF-0001", amount=500000, content=PNG):
    return api.post(
        "/api/v1/driver/deposit-claims",
        {
            "plan_id": str(t.monthly.pk),
            "deposit_account_id": str(t.account.pk),
            "amount_minor": amount,
            "reference": reference,
            "deposited_on": "2026-10-20",
            "receipt": SimpleUploadedFile("receipt.png", content),
        },
        fmt="multipart",
    )


def test_deposit_claim_approval_activates_subscription_and_ledger(ta):
    driver = make_driver(ta, subscribed=False)
    finance_api = api_for(ta, make_member(ta, "finance"))
    r = _claim(api_for(ta, driver.user), ta)
    assert r.status_code == 201 and r.data["status"] == "submitted" and r.data["currency"] == "YER"
    r = finance_api.post(f"/api/v1/admin/deposit-claims/{r.data['id']}/approve")
    assert r.status_code == 200 and r.data["status"] == "approved"
    with tenant_context(ta.tenant):
        sub = DriverSubscription.objects.get(driver=driver)
        assert (sub.ends_at - sub.starts_at).days == 30
        entry = SubscriptionLedgerEntry.objects.get(driver=driver)
        assert entry.entry_type == "subscription_payment" and entry.amount_minor == 500000
    assert api_for(ta, driver.user).get("/api/v1/driver/subscription").data["entitled"] is True
    r = finance_api.post(f"/api/v1/admin/deposit-claims/{r.data['id']}/approve")
    assert r.status_code == 409


def test_duplicate_reference_and_duplicate_receipt_rejected(ta):
    d1, d2 = make_driver(ta, subscribed=False), make_driver(ta, subscribed=False)
    assert _claim(api_for(ta, d1.user), ta, "REF-DUP").status_code == 201
    r = _claim(api_for(ta, d2.user), ta, "ref-dup", content=PDF)  # normalised to upper case
    assert r.status_code == 409 and r.data["code"] == "duplicate_reference"
    r = _claim(api_for(ta, d2.user), ta, "REF-OTHER")  # same PNG bytes as first claim
    assert r.status_code == 409 and r.data["code"] == "duplicate_receipt"


def test_same_reference_allowed_in_another_tenant(ta, tb):
    assert _claim(api_for(ta, make_driver(ta, subscribed=False).user), ta, "REF-SHARED").status_code == 201
    assert _claim(api_for(tb, make_driver(tb, subscribed=False).user), tb, "REF-SHARED").status_code == 201


def test_amount_must_match_plan_price(ta):
    r = _claim(api_for(ta, make_driver(ta, subscribed=False).user), ta, amount=100)
    assert r.status_code == 422 and r.data["code"] == "amount_mismatch"


def test_maker_checker_requires_two_distinct_reviewers(ta):
    with tenant_context(ta.tenant):
        create_config_version(overrides={"subscriptions.dual_approval": True})
    driver = make_driver(ta, subscribed=False)
    claim = _claim(api_for(ta, driver.user), ta).data
    f1 = api_for(ta, make_member(ta, "finance"))
    f2 = api_for(ta, make_member(ta, "finance"))
    r = f1.post(f"/api/v1/admin/deposit-claims/{claim['id']}/approve")
    assert r.data["status"] == "first_approved"
    with tenant_context(ta.tenant):
        assert not DriverSubscription.objects.filter(driver=driver).exists()
    r = f1.post(f"/api/v1/admin/deposit-claims/{claim['id']}/approve")
    assert r.status_code == 422 and r.data["code"] == "same_approver"
    r = f2.post(f"/api/v1/admin/deposit-claims/{claim['id']}/approve")
    assert r.status_code == 200 and r.data["status"] == "approved"


def test_reviewer_cannot_approve_own_deposit(ta):
    user = make_member(ta, "finance")
    driver = make_driver(ta, user=user, subscribed=False)
    claim = _claim(api_for(ta, driver.user), ta).data
    r = api_for(ta, user).post(f"/api/v1/admin/deposit-claims/{claim['id']}/approve")
    assert r.status_code == 422 and r.data["code"] == "self_approval"


def test_rejection_requires_reason_and_reviewer_role(ta):
    claim = _claim(api_for(ta, make_driver(ta, subscribed=False).user), ta).data
    assert (
        api_for(ta, make_member(ta, "reviewer")).post(f"/api/v1/admin/deposit-claims/{claim['id']}/reject", {"note": "x"}).status_code
        == 403
    )
    finance = api_for(ta, make_member(ta, "finance"))
    assert finance.post(f"/api/v1/admin/deposit-claims/{claim['id']}/reject", {}).status_code == 422
    r = finance.post(f"/api/v1/admin/deposit-claims/{claim['id']}/reject", {"note": "not in statement"})
    assert r.data["status"] == "rejected"


def test_founder_trial_once_per_driver_and_capped(ta):
    with tenant_context(ta.tenant):
        create_config_version(overrides={"subscriptions.founder_trial_max_drivers": 1})
    d1, d2 = make_driver(ta, subscribed=False), make_driver(ta, subscribed=False)
    assert api_for(ta, d1.user).post("/api/v1/driver/subscription/trial").status_code == 201
    r = api_for(ta, d1.user).post("/api/v1/driver/subscription/trial")
    assert r.status_code == 409 and r.data["code"] == "trial_used"
    r = api_for(ta, d2.user).post("/api/v1/driver/subscription/trial")
    assert r.status_code == 422 and r.data["code"] == "trial_exhausted"


def test_renewals_extend_from_current_end(ta):
    driver = make_driver(ta)  # already subscribed ~29 days
    finance = api_for(ta, make_member(ta, "finance"))
    claim = _claim(api_for(ta, driver.user), ta).data
    finance.post(f"/api/v1/admin/deposit-claims/{claim['id']}/approve")
    with tenant_context(ta.tenant):
        subs = list(DriverSubscription.objects.filter(driver=driver).order_by("starts_at"))
        assert subs[1].starts_at == subs[0].ends_at


def test_ledger_is_append_only(ta):
    driver = make_driver(ta, subscribed=False)
    api_for(ta, make_member(ta, "finance")).post(
        f"/api/v1/admin/deposit-claims/{_claim(api_for(ta, driver.user), ta).data['id']}/approve"
    )
    with tenant_context(ta.tenant):
        entry = SubscriptionLedgerEntry.objects.get()
        with pytest.raises(RuntimeError):
            entry.note = "edited"
            entry.save()
        from django.db import DatabaseError, connection, transaction

        with pytest.raises(DatabaseError, match="append-only"), transaction.atomic(), connection.cursor() as cursor:
            cursor.execute("UPDATE subscriptions_subscriptionledgerentry SET note='x'")


def test_admin_plan_management_permissions(ta):
    body = {"code": "weekly", "name": "Weekly", "price_minor": 150000, "duration_days": 7}
    assert api_for(ta, make_member(ta, "support")).post("/api/v1/admin/subscription-plans", body).status_code == 403
    r = api_for(ta, make_member(ta, "finance")).post("/api/v1/admin/subscription-plans", body)
    assert r.status_code == 201
