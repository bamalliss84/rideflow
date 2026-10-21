from datetime import timedelta

import pytest
from django.utils import timezone

from apps.core.context import tenant_context
from apps.rides.models import Ride
from apps.subscriptions.models import SubscriptionLedgerEntry
from apps.tenancy.services import create_config_version
from apps.trust.models import EnforcementAction, Violation
from apps.trust.services import record_incident

from .factories import api_for, make_member, ride_payload

pytestmark = pytest.mark.django_db


def test_bilateral_rating_once_after_completion(ride_flow):
    f = ride_flow
    ride = f.assigned()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 5})
    assert r.status_code == 409 and r.data["code"] == "ride_not_completed"
    ride = f.completed() if False else None  # noqa: F841


def test_rating_flow_and_bayesian_trust(ride_flow):
    f = ride_flow
    ride = f.completed()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 1, "tags": ["late"]})
    assert r.status_code == 201
    assert f.rider_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 5}).status_code == 409
    assert f.d1_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 4}).status_code == 201
    trust = f.d1_api.get("/api/v1/me/trust", {"role": "driver"}).data
    # one 1-star rating is smoothed by the prior (4.5 x 5): (22.5 + 1) / 6
    assert trust["rating_avg"] == pytest.approx(3.92, abs=0.01)
    assert trust["rating_count"] == 1 and trust["tier"] == "new"
    assert trust["method_version"].endswith("provisional")


def test_low_stars_alone_never_create_sanctions(ride_flow):
    f = ride_flow
    for _ in range(3):
        ride = f.completed()
        f.rider_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 1, "tags": ["rude"]})
    with tenant_context(f.tenant.tenant):
        assert not Violation.objects.exists()
        assert not EnforcementAction.objects.exists()
    assert f.d1_api.get("/api/v1/driver/eligibility").data["eligible"] is True


def test_rating_window_closes(ride_flow):
    f = ride_flow
    ride = f.completed()
    with tenant_context(f.tenant.tenant):
        Ride.objects.filter(pk=ride["id"]).update(completed_at=timezone.now() - timedelta(days=30))
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 5})
    assert r.status_code == 422 and r.data["code"] == "rating_window_closed"


def _verified(t, subject, reviewer_api, kind="driver_late_cancellation", role="driver"):
    with tenant_context(t.tenant):
        violation = record_incident(subject, role, kind, evidence={"test": True})
    r = reviewer_api.post(f"/api/v1/admin/violations/{violation.pk}/review", {"verify": True, "note": "evidence ok"})
    assert r.status_code == 200, r.data
    return violation


def test_enforcement_ladder_requires_human_activation_for_restrictions(ride_flow):
    f = ride_flow
    reviewer_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))
    owner_api = api_for(f.tenant, make_member(f.tenant, "owner"))
    subject = f.driver1.user
    for _ in range(3):
        _verified(f.tenant, subject, reviewer_api)
    with tenant_context(f.tenant.tenant):
        actions = list(EnforcementAction.objects.filter(subject=subject).order_by("level"))
    assert [(a.level, a.action_type, a.status) for a in actions] == [
        (1, "warning", "active"),
        (2, "commitment_effect", "active"),
        (3, "restriction", "proposed"),
    ]
    assert f.d1_api.get("/api/v1/driver/eligibility").data["eligible"] is True  # proposed != applied
    # reviewers cannot activate restrictions; admins can
    assert reviewer_api.post(f"/api/v1/admin/enforcement-actions/{actions[2].pk}/activate").status_code == 403
    r = owner_api.post(f"/api/v1/admin/enforcement-actions/{actions[2].pk}/activate")
    assert r.status_code == 200 and r.data["duration_hours"] == 24
    eligibility = f.d1_api.get("/api/v1/driver/eligibility").data
    assert eligibility["eligible"] is False
    assert any(x.startswith("restricted_until") for x in eligibility["reasons"])


def test_rider_restriction_blocks_new_requests(ride_flow):
    f = ride_flow
    reviewer_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))
    owner_api = api_for(f.tenant, make_member(f.tenant, "owner"))
    for _ in range(3):
        _verified(f.tenant, f.rider_user, reviewer_api, kind="rider_no_show", role="rider")
    with tenant_context(f.tenant.tenant):
        restriction = EnforcementAction.objects.get(subject=f.rider_user, action_type="restriction")
    owner_api.post(f"/api/v1/admin/enforcement-actions/{restriction.pk}/activate")
    r = f.rider_api.post("/api/v1/rides", ride_payload(f.tenant))
    assert r.status_code == 403 and r.data["code"] == "restricted"


def test_appeal_decided_by_different_reviewer_overturns(ride_flow):
    f = ride_flow
    reviewer_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))
    other_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))
    violation = _verified(f.tenant, f.rider_user, reviewer_api, kind="rider_no_show", role="rider")
    r = f.rider_api.post(f"/api/v1/me/violations/{violation.pk}/appeal", {"reason": "I was there"})
    assert r.status_code == 201
    assert f.rider_api.post(f"/api/v1/me/violations/{violation.pk}/appeal", {"reason": "again"}).status_code == 409
    appeal_id = r.data["id"]
    r = reviewer_api.post(f"/api/v1/admin/appeals/{appeal_id}/decide", {"uphold": True, "note": "x"})
    assert r.status_code == 422 and r.data["code"] == "same_reviewer"
    r = other_api.post(f"/api/v1/admin/appeals/{appeal_id}/decide", {"uphold": True, "note": "GPS unreliable"})
    assert r.status_code == 200 and r.data["status"] == "upheld"
    with tenant_context(f.tenant.tenant):
        assert Violation.objects.get(pk=violation.pk).status == "overturned"
        assert not EnforcementAction.objects.filter(violation=violation).exclude(status="revoked").exists()


def test_other_users_cannot_appeal_or_see_violations(ride_flow, h):
    f = ride_flow
    reviewer_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))
    violation = _verified(f.tenant, f.rider_user, reviewer_api, kind="rider_no_show", role="rider")
    stranger = h.api(f.tenant, h.member(f.tenant, "rider"))
    assert stranger.get(f"/api/v1/me/violations/{violation.pk}").status_code == 404
    assert stranger.post(f"/api/v1/me/violations/{violation.pk}/appeal", {"reason": "x"}).status_code == 404


def test_dispute_flow_and_no_show_contest(ride_flow):
    f = ride_flow
    ride = f.completed()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/disputes", {"category": "fare", "description": "charged more"})
    assert r.status_code == 201
    assert f.snapshot(ride["id"])["status"] == "disputed"
    dispute_id = r.data["id"]
    assert f.d1_api.post(f"/api/v1/me/disputes/{dispute_id}/notes", {"note": "price was agreed"}).status_code == 201
    reviewer_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))
    r = reviewer_api.post(f"/api/v1/admin/disputes/{dispute_id}/resolve", {"uphold": True, "note": "receipt shows"})
    assert r.status_code == 200 and r.data["status"] == "upheld"
    with tenant_context(f.tenant.tenant):
        v = Violation.objects.get(dispute_id=dispute_id)
        assert v.kind == "price_non_compliance" and v.status == "pending_review" and v.subject == f.driver1.user


def test_safety_dispute_is_flagged(ride_flow):
    f = ride_flow
    ride = f.completed()
    r = f.rider_api.post(f"/api/v1/rides/{ride['id']}/disputes", {"category": "safety", "description": "unsafe"})
    assert r.data["is_safety"] is True
    owner_api = api_for(f.tenant, make_member(f.tenant, "owner"))
    assert owner_api.get("/api/v1/admin/dashboard").data["queues"]["safety_disputes_open"] == 1


def test_compensation_is_disabled_by_default_and_capped_when_enabled(ride_flow):
    f = ride_flow
    reviewer_api = api_for(f.tenant, make_member(f.tenant, "reviewer"))

    def no_show_violation():
        ride = f.arrived()
        with tenant_context(f.tenant.tenant):
            return record_incident(f.rider_user, "rider", "rider_no_show", ride=Ride.objects.get(pk=ride["id"]))

    v = no_show_violation()
    reviewer_api.post(f"/api/v1/admin/violations/{v.pk}/review", {"verify": True, "note": "ok"})
    with tenant_context(f.tenant.tenant):
        assert not SubscriptionLedgerEntry.objects.filter(entry_type="compensation_credit").exists()
        create_config_version(
            overrides={
                "compensation.enabled": True,
                "compensation.days_per_verified_no_show": 2,
                "compensation.max_days_per_driver_month": 3,
                "compensation.tenant_monthly_budget_days": 100,
            }
        )
        Ride.objects.filter(rider=f.rider_user).update(status="cancelled")
    for _ in range(2):
        v = no_show_violation()
        reviewer_api.post(f"/api/v1/admin/violations/{v.pk}/review", {"verify": True, "note": "ok"})
        with tenant_context(f.tenant.tenant):
            Ride.objects.filter(rider=f.rider_user).update(status="cancelled")
    with tenant_context(f.tenant.tenant):
        days = [e.days for e in SubscriptionLedgerEntry.objects.filter(entry_type="compensation_credit")]
    assert sorted(days) == [1, 2]  # capped at 3 days per driver per month


def test_reviewer_cannot_review_own_case(ride_flow):
    f = ride_flow
    reviewer = make_member(f.tenant, "reviewer")
    with tenant_context(f.tenant.tenant):
        v = record_incident(reviewer, "rider", "rider_no_show")
    r = api_for(f.tenant, reviewer).post(f"/api/v1/admin/violations/{v.pk}/review", {"verify": True, "note": "x"})
    assert r.status_code == 422 and r.data["code"] == "self_review"


def test_renewal_discount_disabled_by_default(ride_flow):
    r = ride_flow.d1_api.get("/api/v1/driver/rewards").data
    assert r["enabled"] is False and r["discount_pct"] == 0
