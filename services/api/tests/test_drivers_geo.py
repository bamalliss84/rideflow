from datetime import timedelta

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from apps.core.context import tenant_context
from apps.drivers.models import DriverDocument, DriverProfile
from apps.geo.models import DriverLocation
from apps.subscriptions.models import DriverSubscription

from .factories import PDF, PNG, api_for, make_driver, make_member, make_user, ride_payload

pytestmark = pytest.mark.django_db


def _upload(api, doc_type, content=PNG, name="d.png", vehicle_id=None):
    data = {"doc_type": doc_type, "number": "123", "expires_at": "2030-01-01", "file": SimpleUploadedFile(name, content)}
    if vehicle_id:
        data["vehicle_id"] = vehicle_id
    return api.post("/api/v1/driver/documents", data, fmt="multipart")


def test_driver_onboarding_review_and_go_online(ta):
    user = make_member(ta, "driver")
    with tenant_context(ta.tenant):
        DriverProfile.objects.create(user=user)
    driver_api = api_for(ta, user)
    reviewer_api = api_for(ta, make_member(ta, "reviewer"))

    assert driver_api.post("/api/v1/driver/submit").data["code"] == "documents_missing"
    vehicle = driver_api.post("/api/v1/driver/vehicles", {"plate_number": "abc 1", "make": "Kia", "model": "Rio", "color": "Red"})
    assert vehicle.status_code == 201 and vehicle.data["plate_number"] == "ABC 1"
    assert _upload(driver_api, "national_id").status_code == 201
    assert _upload(driver_api, "driving_license", PDF, "l.pdf").status_code == 201
    assert _upload(driver_api, "vehicle_registration", vehicle_id=vehicle.data["id"]).status_code == 201
    r = driver_api.post("/api/v1/driver/submit")
    assert r.status_code == 200 and r.data["status"] == "under_review"

    driver_id = r.data["id"]
    r = reviewer_api.post(f"/api/v1/admin/drivers/{driver_id}/decide", {"decision": "approve"})
    assert r.status_code == 422 and r.data["code"] == "documents_not_approved"
    for doc in reviewer_api.get("/api/v1/admin/driver-documents", {"driver": driver_id}).data["results"]:
        assert reviewer_api.post(f"/api/v1/admin/driver-documents/{doc['id']}/approve").status_code == 200
    assert reviewer_api.post(f"/api/v1/admin/vehicles/{vehicle.data['id']}/approve").status_code == 200
    r = reviewer_api.post(f"/api/v1/admin/drivers/{driver_id}/decide", {"decision": "approve"})
    assert r.status_code == 200 and r.data["status"] == "approved"

    # Approved but no subscription: entitlement check blocks going online (D003).
    r = driver_api.post("/api/v1/driver/availability", {"online": True})
    assert r.status_code == 403 and "subscription_inactive" in r.data["detail"]["reasons"]
    assert driver_api.post("/api/v1/driver/subscription/trial").status_code == 201
    # Eligible, but no location yet: going online is refused (the driver would be invisible to dispatch).
    r = driver_api.post("/api/v1/driver/availability", {"online": True})
    assert r.status_code == 403 and r.data["detail"]["reasons"] == ["location_required"]
    lng, lat = ta.center
    assert driver_api.post("/api/v1/driver/location", {"lat": lat, "lng": lng, "accuracy_m": 10}).data["applied"] is True
    r = driver_api.post("/api/v1/driver/availability", {"online": True})
    assert r.status_code == 200 and r.data["eligible"] is True and r.data["is_online"] is True
    assert r.data["presence"]["fresh"] is True and r.data["presence"]["has_location"] is True


def test_upload_rejects_disguised_or_oversized_files(ta, settings):
    driver = make_driver(ta, approved=False)
    api = api_for(ta, driver.user)
    r = _upload(api, "national_id", b"MZ\x90\x00 not an image", "evil.png")
    assert r.status_code == 400
    settings.UPLOAD_MAX_BYTES = 10
    assert _upload(api, "national_id").status_code == 400


def test_document_rejection_requires_reason(ta):
    driver = make_driver(ta, approved=False)
    reviewer_api = api_for(ta, make_member(ta, "reviewer"))
    with tenant_context(ta.tenant):
        doc = DriverDocument.objects.filter(driver=driver).first()
    r = reviewer_api.post(f"/api/v1/admin/driver-documents/{doc.pk}/reject", {})
    assert r.status_code == 422 and r.data["code"] == "reason_required"


def test_document_expiry_mid_shift_blocks_bidding_and_confirmation(ta):
    driver = make_driver(ta)
    rider_api = api_for(ta, make_member(ta, "rider"))
    ride = rider_api.post("/api/v1/rides", ride_payload(ta)).data
    with tenant_context(ta.tenant):
        DriverDocument.objects.filter(driver=driver, doc_type="driving_license").update(
            expires_at=timezone.localdate() - timedelta(days=1)
        )
    r = api_for(ta, driver.user).post(f"/api/v1/rides/{ride['id']}/bids", {"amount_minor": 1000, "eta_seconds": 60})
    assert r.status_code == 403
    assert any(x.startswith("documents_missing_or_expired") for x in r.data["detail"]["reasons"])


def test_subscription_expiry_removes_entitlement(ta):
    driver = make_driver(ta)
    api = api_for(ta, driver.user)
    assert api.get("/api/v1/driver/eligibility").data["eligible"] is True
    with tenant_context(ta.tenant):
        DriverSubscription.objects.filter(driver=driver).update(ends_at=timezone.now() - timedelta(hours=1))
    body = api.get("/api/v1/driver/eligibility").data
    assert body["eligible"] is False and "subscription_inactive" in body["reasons"]


def test_driver_cannot_review_and_rider_cannot_use_driver_endpoints(ta):
    driver = make_driver(ta)
    rider = make_member(ta, "rider")
    assert api_for(ta, driver.user).get("/api/v1/admin/drivers").status_code == 403
    assert api_for(ta, rider).get("/api/v1/driver/profile").status_code == 403
    assert api_for(ta, rider).post("/api/v1/driver/location", {"lat": 1, "lng": 1, "accuracy_m": 5}).status_code == 403


def test_location_updates_ignore_out_of_order_and_skewed_clocks(ta):
    driver = make_driver(ta)
    api = api_for(ta, driver.user)
    lng, lat = ta.center
    now = timezone.now()
    r = api.post("/api/v1/driver/location", {"lat": lat, "lng": lng, "accuracy_m": 5, "device_ts": now.isoformat()})
    assert r.data["applied"] is True
    r = api.post(
        "/api/v1/driver/location",
        {"lat": lat + 1, "lng": lng, "accuracy_m": 5, "device_ts": (now - timedelta(seconds=30)).isoformat()},
    )
    assert r.data["applied"] is False  # older fix arrived late: ignored
    with tenant_context(ta.tenant):
        assert abs(DriverLocation.objects.get(driver=driver).point.y - lat) < 1e-6
    future = now + timedelta(hours=3)
    r = api.post("/api/v1/driver/location", {"lat": lat, "lng": lng + 0.001, "accuracy_m": 5, "device_ts": future.isoformat()})
    assert r.data["applied"] is True
    with tenant_context(ta.tenant):
        assert DriverLocation.objects.get(driver=driver).device_ts <= timezone.now()


def test_nearby_drivers_is_coarse_for_riders_and_detailed_for_staff(ta):
    make_driver(ta, offset=(0.001, 0.001))
    make_driver(ta, offset=(0.3, 0.3))  # far away
    make_driver(ta, offset=(0.002, 0.0), online=False)
    lng, lat = ta.center
    rider_api = api_for(ta, make_member(ta, "rider"))
    body = rider_api.get("/api/v1/drivers/nearby", {"lat": lat, "lng": lng, "radius_m": 2000}).data
    assert body["count"] == 1
    assert set(body["drivers"][0]) == {"lat", "lng"}
    staff = (
        api_for(ta, make_member(ta, "reviewer")).get("/api/v1/admin/drivers-nearby", {"lat": lat, "lng": lng, "radius_m": 2000}).data
    )
    assert len(staff) == 1 and staff[0]["distance_m"] < 300


def test_stale_presence_is_not_dispatched(ta):
    driver = make_driver(ta)
    with tenant_context(ta.tenant):
        DriverLocation.objects.filter(driver=driver).update(server_ts=timezone.now() - timedelta(minutes=10))
    ride = api_for(ta, make_member(ta, "rider")).post("/api/v1/rides", ride_payload(ta)).data
    assert ride["status"] == "requested"  # nobody fresh to dispatch to


def test_fare_estimate_and_service_area(ta):
    rider_api = api_for(ta, make_member(ta, "rider"))
    lng, lat = ta.center
    r = rider_api.post("/api/v1/fare-estimate", {"pickup": {"lat": lat, "lng": lng}, "dropoff": {"lat": lat + 0.05, "lng": lng}})
    assert r.status_code == 200
    assert r.data["is_estimate"] is True and r.data["currency"] == "YER"
    assert 5000 < r.data["distance_m"] < 6000
    r = rider_api.post("/api/v1/fare-estimate", {"pickup": {"lat": lat + 5, "lng": lng}, "dropoff": {"lat": lat, "lng": lng}})
    assert r.status_code == 422 and r.data["code"] == "outside_service_area"


def test_dispatch_waves_expand_radius_and_cap(ta):
    near = make_driver(ta, offset=(0.001, 0.0))
    mid = make_driver(ta, offset=(0.04, 0.0))  # ~4.3 km: outside wave 1 (3 km), inside wave 2 (5 km)
    rider_api = api_for(ta, make_member(ta, "rider"))
    ride = rider_api.post("/api/v1/rides", ride_payload(ta)).data
    assert api_for(ta, mid.user).get("/api/v1/driver/ride-offers").data == []
    assert len(api_for(ta, near.user).get("/api/v1/driver/ride-offers").data) == 1
    assert rider_api.post(f"/api/v1/rides/{ride['id']}/dispatch").status_code == 200
    assert len(api_for(ta, mid.user).get("/api/v1/driver/ride-offers").data) == 1
    assert rider_api.post(f"/api/v1/rides/{ride['id']}/dispatch").status_code == 200
    r = rider_api.post(f"/api/v1/rides/{ride['id']}/dispatch")
    assert r.status_code == 422 and r.data["code"] == "max_waves_reached"


def test_driver_never_dispatched_own_ride(ta):
    user = make_user("Both roles")
    driver = make_driver(ta, user=user)
    from .factories import add_roles

    add_roles(ta, user, "rider")
    ride = api_for(ta, user).post("/api/v1/rides", ride_payload(ta)).data
    assert ride["status"] == "requested"
    assert api_for(ta, driver.user).get("/api/v1/driver/ride-offers").data == []
