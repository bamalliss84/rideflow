"""D052: plans that show their value, reminders before the end, a short grace, and free days for inviting drivers."""

from datetime import timedelta

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.core.context import tenant_context
from apps.notifications.models import Notification
from apps.subscriptions import services
from apps.subscriptions.models import DriverSubscription, SubscriptionLedgerEntry, SubscriptionPlan, SubscriptionSource
from apps.tenancy.policy import validate_overrides
from apps.tenancy.services import create_config_version

from .factories import PNG, api_for, make_driver, make_member

pytestmark = pytest.mark.django_db


def set_policy(t, **params):
    with tenant_context(t.tenant):
        create_config_version(overrides=params)


def kinds(t, driver):
    with tenant_context(t.tenant):
        return list(Notification.objects.filter(user=driver.user).order_by("id").values_list("kind", flat=True))


def cover(t, driver, ends_in):
    """Replace the driver's cover with one that ends `ends_in` from now."""
    now = timezone.now()
    with tenant_context(t.tenant):
        DriverSubscription.objects.filter(driver=driver).delete()
        DriverSubscription.objects.create(
            driver=driver, starts_at=now - timedelta(days=20), ends_at=now + ends_in, source=SubscriptionSource.MANUAL
        )


def remind(t, now=None):
    with tenant_context(t.tenant):
        return services.send_reminders(now)


# ---------------------------------------------------------------- plan value


def test_longer_plans_show_their_saving_and_the_best_value(ta):
    with tenant_context(ta.tenant):
        SubscriptionPlan.objects.create(code="weekly", name="Weekly", price_minor=140000, duration_days=7)
        SubscriptionPlan.objects.create(code="quarter", name="Quarter", price_minor=1200000, duration_days=90)
    driver = make_driver(ta)
    plans = {p["code"]: p for p in api_for(ta, driver.user).get("/api/v1/driver/subscription").data["plans"]}
    assert plans["weekly"]["per_day_minor"] == 20000 and plans["weekly"]["saving_pct"] == 0
    assert plans["monthly"]["per_day_minor"] == 16667 and plans["monthly"]["saving_pct"] == 17
    assert plans["quarter"]["per_day_minor"] == 13333 and plans["quarter"]["saving_pct"] == 33
    assert [c for c, p in plans.items() if p["best_value"]] == ["quarter"]
    assert plans["trial"]["best_value"] is False and plans["trial"]["per_day_minor"] == 0


def test_a_single_paid_plan_is_not_called_the_best_value(ta):
    driver = make_driver(ta)
    plans = api_for(ta, driver.user).get("/api/v1/driver/subscription").data["plans"]
    assert not any(p["best_value"] for p in plans)


def test_the_overview_weighs_the_plan_against_recent_earnings(ride_flow):
    f = ride_flow
    data = f.d1_api.get("/api/v1/driver/subscription").data
    assert data["earnings"] == {"days": 30, "trips": 0, "earned_minor": 0}
    f.completed()
    data = f.d1_api.get("/api/v1/driver/subscription").data
    assert data["earnings"]["trips"] == 1 and data["earnings"]["earned_minor"] == 150000
    assert data["cover_ends_at"] is not None and data["grace_days"] == 1 and data["in_grace"] is False


# ---------------------------------------------------------------- grace


def test_a_day_of_grace_by_default_and_none_when_the_operator_says_so(ta):
    driver = make_driver(ta)
    cover(ta, driver, -timedelta(hours=5))
    api = api_for(ta, driver.user)
    data = api.get("/api/v1/driver/subscription").data
    assert data["entitled"] is True and data["in_grace"] is True
    assert data["grace_days"] == 1 and data["reminder_days"] == [3, 1]
    set_policy(ta, **{"subscriptions.grace_days": 0})
    assert api.get("/api/v1/driver/subscription").data["entitled"] is False


# ---------------------------------------------------------------- reminders


def test_reminded_three_days_and_one_day_before_then_when_it_ends(ta):
    driver = make_driver(ta)
    cover(ta, driver, timedelta(days=10))
    assert remind(ta) == 0
    end = timezone.now() + timedelta(days=10)
    assert remind(ta, end - timedelta(days=3)) == 1
    assert remind(ta, end - timedelta(days=3) + timedelta(hours=1)) == 0, "never twice"
    assert remind(ta, end - timedelta(hours=20)) == 1
    assert remind(ta, end + timedelta(minutes=5)) == 1
    assert kinds(ta, driver) == ["subscription.expiring", "subscription.expiring", "subscription.expired"]
    with tenant_context(ta.tenant):
        first = Notification.objects.filter(user=driver.user).order_by("id").first()
    assert first.payload["days_left"] == 3


def test_a_worker_back_after_a_gap_sends_only_the_nearest_reminder(ta):
    driver = make_driver(ta)
    cover(ta, driver, timedelta(hours=12))
    assert remind(ta) == 1
    assert remind(ta) == 0
    assert kinds(ta, driver) == ["subscription.expiring"]


def test_a_renewal_starts_its_own_reminders(ta):
    driver = make_driver(ta)
    cover(ta, driver, timedelta(hours=12))
    remind(ta)
    with tenant_context(ta.tenant):
        services._extend(driver, days=30, source=SubscriptionSource.MANUAL)
    assert remind(ta) == 0, "the new end is a month away"
    assert remind(ta, timezone.now() + timedelta(days=29, hours=13)) == 1


def test_reminder_days_are_checked():
    validate_overrides({"subscriptions.reminder_days": [7, 3, 1]})
    for bad in ([0], [31], [1, 1], [1, 2, 3, 4, 5, 6], ["3"]):
        with pytest.raises(ValidationError):
            validate_overrides({"subscriptions.reminder_days": bad})


def test_the_worker_reminds_every_operator(ta, tb):
    a = make_driver(ta)
    b = make_driver(tb)
    cover(ta, a, timedelta(hours=10))
    cover(tb, b, timedelta(hours=10))
    assert services.process_all_reminders(force=True) == 2


# ---------------------------------------------------------------- invitations


def _pay_first_plan(t, driver, reference="REF-INV-1"):
    api = api_for(t, driver.user)
    r = api.post(
        "/api/v1/driver/deposit-claims",
        {
            "plan_id": str(t.monthly.pk),
            "deposit_account_id": str(t.account.pk),
            "amount_minor": 500000,
            "reference": reference,
            "deposited_on": "2026-11-10",
            "receipt": SimpleUploadedFile("receipt.png", PNG + reference.encode()),
        },
        fmt="multipart",
    )
    assert r.status_code == 201, r.data
    finance = api_for(t, make_member(t, "finance"))
    assert finance.post(f"/api/v1/admin/deposit-claims/{r.data['id']}/approve").status_code == 200


def test_an_inviter_gets_free_days_when_the_invitee_pays_a_first_plan(ta):
    inviter = make_driver(ta)
    newcomer = make_driver(ta, subscribed=False)
    code = api_for(ta, inviter.user).get("/api/v1/driver/subscription").data["referral"]["code"]
    assert len(code) == 6
    r = api_for(ta, newcomer.user).post("/api/v1/driver/subscription/referral", {"code": code.lower()})
    assert r.status_code == 200 and r.data["can_enter_code"] is False
    with tenant_context(ta.tenant):
        before = services.cover_ends_at(inviter)
    _pay_first_plan(ta, newcomer)
    with tenant_context(ta.tenant):
        assert services.cover_ends_at(inviter) - before == timedelta(days=7)
        entry = SubscriptionLedgerEntry.objects.get(driver=inviter, entry_type="referral_credit")
        assert entry.days == 7
    assert "subscription.referral_reward" in kinds(ta, inviter)
    summary = api_for(ta, inviter.user).get("/api/v1/driver/subscription").data["referral"]
    assert summary["invited"] == 1 and summary["rewarded"] == 1 and summary["days_earned"] == 7
    # A renewal by the same newcomer pays nothing more.
    _pay_first_plan(ta, newcomer, reference="REF-INV-2")
    with tenant_context(ta.tenant):
        assert SubscriptionLedgerEntry.objects.filter(driver=inviter, entry_type="referral_credit").count() == 1


def test_codes_are_checked(ta, tb):
    me = make_driver(ta, subscribed=False)
    api = api_for(ta, me.user)
    own = api.get("/api/v1/driver/subscription").data["referral"]["code"]
    assert api.post("/api/v1/driver/subscription/referral", {"code": own}).data["code"] == "referral_self"
    assert api.post("/api/v1/driver/subscription/referral", {"code": "ZZZZZZ"}).data["code"] == "referral_invalid"
    other_operator = make_driver(tb)
    foreign = api_for(tb, other_operator.user).get("/api/v1/driver/subscription").data["referral"]["code"]
    assert api.post("/api/v1/driver/subscription/referral", {"code": foreign}).data["code"] == "referral_invalid"
    inviter = make_driver(ta)
    good = api_for(ta, inviter.user).get("/api/v1/driver/subscription").data["referral"]["code"]
    assert api.post("/api/v1/driver/subscription/referral", {"code": good}).status_code == 200
    assert api.post("/api/v1/driver/subscription/referral", {"code": good}).status_code == 409


def test_too_late_after_a_paid_plan(ta):
    inviter = make_driver(ta)
    driver = make_driver(ta, subscribed=False)
    _pay_first_plan(ta, driver)
    good = api_for(ta, inviter.user).get("/api/v1/driver/subscription").data["referral"]["code"]
    assert api_for(ta, driver.user).post("/api/v1/driver/subscription/referral", {"code": good}).data["code"] == "referral_too_late"


def test_invitations_off_when_the_operator_sets_zero_days(ta):
    set_policy(ta, **{"rewards.referral_days": 0})
    driver = make_driver(ta)
    referral = api_for(ta, driver.user).get("/api/v1/driver/subscription").data["referral"]
    assert referral["code"] == "" and referral["can_enter_code"] is False
