"""Builds a tenant populated (through the real API) with at least one object of every tenant-scoped type."""

from datetime import timedelta
from types import SimpleNamespace

from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from apps.core.context import tenant_context
from apps.core.models import AuditEvent
from apps.drivers.models import DriverDocument, Vehicle
from apps.notifications.models import Notification
from apps.rides.models import Bid, Ride, RideAmendment
from apps.subscriptions.models import DepositClaim, DriverSubscription, SubscriptionLedgerEntry
from apps.tenancy.models import TenantConfig, TenantMembership
from apps.trust.models import Appeal, Dispute, EnforcementAction, TrustSnapshot, Violation

from .factories import PDF, api_for, make_driver, make_member, ride_payload


def populate(t):
    owner = make_member(t, "owner", name="Owner")
    reviewer = make_member(t, "reviewer", name="Reviewer")
    rider = make_member(t, "rider", name="Rider")
    driver = make_driver(t)
    owner_api, reviewer_api, rider_api, driver_api = (api_for(t, u) for u in (owner, reviewer, rider, driver.user))

    assert owner_api.post("/api/v1/admin/config", {"params": {"bids.expiry_seconds": 300}}).status_code == 201

    ride = rider_api.post("/api/v1/rides", ride_payload(t)).data
    bid = driver_api.post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 100000, "eta_seconds": 120}).data
    r = rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
    r = driver_api.post(f"/api/v1/rides/{ride['id']}/confirm", {"expected_version": r.data["version"]})
    amendment = driver_api.post(f"/api/v1/rides/{ride['id']}/amendments", {"new_fare_minor": 110000, "reason": "detour"}).data
    lng, lat = t.center
    r = driver_api.post(
        f"/api/v1/rides/{ride['id']}/arrive", {"expected_version": r.data["version"], "lat": lat, "lng": lng, "accuracy_m": 5}
    )
    r = driver_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": r.data["version"]})
    r = driver_api.post(f"/api/v1/rides/{ride['id']}/complete", {"expected_version": r.data["version"]})
    assert r.status_code == 200, r.data
    rider_api.post(f"/api/v1/rides/{ride['id']}/rating", {"stars": 5})
    dispute = rider_api.post(f"/api/v1/rides/{ride['id']}/disputes", {"category": "behavior", "description": "rude"}).data

    # second ride: late rider cancellation -> violation -> verify -> enforcement -> appeal
    ride2 = rider_api.post("/api/v1/rides", ride_payload(t)).data
    bid2 = driver_api.post(f"/api/v1/rides/{ride2['id']}/bids", {"amount_minor": 90000, "eta_seconds": 60}).data
    r = rider_api.post(f"/api/v1/rides/{ride2['id']}/select", {"bid_id": bid2["id"], "expected_version": ride2["version"]})
    r = driver_api.post(f"/api/v1/rides/{ride2['id']}/confirm", {"expected_version": r.data["version"]})
    with tenant_context(t.tenant):
        Ride.objects.filter(pk=ride2["id"]).update(assigned_at=timezone.now() - timedelta(minutes=10))
    rider_api.post(f"/api/v1/rides/{ride2['id']}/cancel", {"expected_version": r.data["version"], "reason": "late"})
    with tenant_context(t.tenant):
        violation = Violation.objects.get(ride_id=ride2["id"])
    assert (
        reviewer_api.post(f"/api/v1/admin/violations/{violation.pk}/review", {"verify": True, "note": "verified"}).status_code == 200
    )
    appeal = rider_api.post(f"/api/v1/me/violations/{violation.pk}/appeal", {"reason": "please"}).data

    receipt = SimpleUploadedFile("r.pdf", PDF + t.tenant.slug.encode(), content_type="application/pdf")
    claim = driver_api.post(
        "/api/v1/driver/deposit-claims",
        {
            "plan_id": str(t.monthly.pk),
            "deposit_account_id": str(t.account.pk),
            "amount_minor": 500000,
            "reference": f"REF-{t.tenant.slug}-1",
            "deposited_on": "2026-10-01",
            "receipt": receipt,
        },
        fmt="multipart",
    )
    assert claim.status_code == 201, claim.data
    assert owner_api.post(f"/api/v1/admin/deposit-claims/{claim.data['id']}/approve").status_code == 200

    with tenant_context(t.tenant):
        objects = SimpleNamespace(
            ride=Ride.objects.get(pk=ride["id"]),
            bid=Bid.objects.get(pk=bid["id"]),
            amendment=RideAmendment.objects.get(pk=amendment["id"]),
            driver=driver,
            vehicle=Vehicle.objects.filter(driver=driver).first(),
            document=DriverDocument.objects.filter(driver=driver).first(),
            claim=DepositClaim.objects.get(pk=claim.data["id"]),
            subscription=DriverSubscription.objects.filter(driver=driver).first(),
            ledger=SubscriptionLedgerEntry.objects.filter(driver=driver).first(),
            violation=violation,
            enforcement=EnforcementAction.objects.get(violation=violation),
            appeal=Appeal.objects.get(pk=appeal["id"]),
            dispute=Dispute.objects.get(pk=dispute["id"]),
            snapshot=TrustSnapshot.objects.first(),
            membership=TenantMembership.objects.get(user=owner, role="owner"),
            config=TenantConfig.objects.first(),
            audit=AuditEvent.objects.filter(tenant=t.tenant).first(),
            notification=Notification.objects.first(),
            city=t.city,
            area=t.city.service_areas.first(),
            plan=t.monthly,
            account=t.account,
        )
    return SimpleNamespace(
        t=t, owner=owner, rider=rider, driver=driver, objects=objects, owner_api=owner_api, rider_api=rider_api, driver_api=driver_api
    )
