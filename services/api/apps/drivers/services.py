from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from apps.core import audit
from apps.core.context import require_tenant
from apps.core.exceptions import BusinessRuleViolation, Conflict, NotEligible
from apps.tenancy.policy import current_policy

from .models import DocumentType, DriverDocument, DriverProfile, DriverStatus, ReviewStatus, Vehicle


def ensure_driver_profile(user):
    profile, _ = DriverProfile.objects.get_or_create(user=user, tenant=require_tenant())
    return profile


def get_driver_for_user(user):
    profile = DriverProfile.objects.filter(user=user).first()
    if profile is None:
        raise NotEligible("No driver profile for this operator.", code="no_driver_profile")
    return profile


def _valid_documents(driver, today=None):
    today = today or timezone.localdate()
    docs = DriverDocument.objects.filter(driver=driver, status=ReviewStatus.APPROVED)
    return {d.doc_type for d in docs if d.expires_at is None or d.expires_at >= today}


def eligibility(driver, policy=None):
    """Server-side eligibility to go online / bid. Returns reasons so the app can guide the driver."""
    from apps.subscriptions.services import has_entitlement
    from apps.trust.services import active_restriction

    policy = policy or current_policy()
    reasons = []
    if driver.status != DriverStatus.APPROVED:
        reasons.append(f"driver_{driver.status}")
    missing = set(policy["drivers.required_documents"]) - _valid_documents(driver)
    if missing:
        reasons.append("documents_missing_or_expired:" + ",".join(sorted(missing)))
    if not Vehicle.objects.filter(driver=driver, status=ReviewStatus.APPROVED, is_active=True).exists():
        reasons.append("no_approved_vehicle")
    entitled = has_entitlement(driver, policy)
    if policy["subscriptions.required_for_online"] and not entitled:
        reasons.append("subscription_inactive")
    restriction = active_restriction(driver.user, "driver")
    if restriction is not None:
        reasons.append("restricted_until:" + restriction.ends_at.isoformat())
    tenant = require_tenant()
    if not tenant.is_active:
        reasons.append("tenant_suspended")
    return {
        "eligible": not reasons,
        "reasons": reasons,
        "subscription_active": entitled,
        "status": driver.status,
        "is_online": driver.is_online,
        "presence": presence(driver, policy),
    }


def presence(driver, policy=None):
    """Location freshness. A driver is only dispatchable with a fix newer than `presence.stale_seconds`
    (the same rule dispatch and the operator's live map use), so the app can show "ready" truthfully."""
    from apps.geo.models import DriverLocation

    policy = policy or current_policy()
    stale_seconds = policy["presence.stale_seconds"]
    location = DriverLocation.objects.filter(driver=driver).only("server_ts", "accuracy_m").first()
    fresh = bool(location and location.server_ts >= timezone.now() - timedelta(seconds=stale_seconds))
    return {
        "has_location": location is not None,
        "fresh": fresh,
        "server_ts": location.server_ts if location else None,
        "accuracy_m": location.accuracy_m if location else None,
        "stale_after_seconds": stale_seconds,
    }


def assert_eligible(driver, policy=None):
    result = eligibility(driver, policy)
    if not result["eligible"]:
        raise NotEligible(detail={"detail": "Driver is not eligible.", "reasons": result["reasons"]})
    return result


def submit_for_review(driver, request=None):
    policy = current_policy()
    if driver.status not in (DriverStatus.PENDING_DOCUMENTS, DriverStatus.REJECTED):
        raise Conflict(f"Cannot submit while {driver.status}.", code="invalid_transition")
    present = set(
        DriverDocument.objects.filter(driver=driver).exclude(status=ReviewStatus.REJECTED).values_list("doc_type", flat=True)
    )
    missing = set(policy["drivers.required_documents"]) - present
    if missing:
        raise BusinessRuleViolation({"missing_documents": sorted(missing)}, code="documents_missing")
    if not Vehicle.objects.filter(driver=driver, is_active=True).exclude(status=ReviewStatus.REJECTED).exists():
        raise BusinessRuleViolation("Register a vehicle first.", code="vehicle_missing")
    driver.status = DriverStatus.UNDER_REVIEW
    driver.submitted_at = timezone.now()
    driver.save(update_fields=["status", "submitted_at", "updated_at"])
    audit.record("driver.submitted", request=request, target=driver)
    from apps.notifications.services import notify_staff

    notify_staff("drivers.review", "staff.driver_submitted", {"driver_id": str(driver.pk), "name": driver.user.full_name})
    return driver


def set_availability(driver, online, request=None):
    with transaction.atomic():
        driver = DriverProfile.objects.select_for_update().get(pk=driver.pk)
        if online:
            assert_eligible(driver)
            # Going online without a fresh position would make the driver "online" but invisible to dispatch.
            if not presence(driver)["fresh"]:
                raise NotEligible(detail={"detail": "Send a current location before going online.", "reasons": ["location_required"]})
            if not driver.is_online:
                driver.is_online = True
                driver.online_since = timezone.now()
        else:
            driver.is_online = False
            driver.online_since = None
        driver.save(update_fields=["is_online", "online_since", "updated_at"])
    audit.record("driver.availability", request=request, target=driver, data={"online": online})
    return driver


def _notify_driver(driver, kind, payload):
    from apps.notifications.services import notify

    notify(driver.user, kind, payload)


# The application is a draft until the driver explicitly submits it (pending_documents / rejected -> under_review).
# Draft uploads are not reviewable; documents of approved/suspended drivers stay reviewable (renewals).
REVIEWABLE_DRIVER_STATUSES = (DriverStatus.UNDER_REVIEW, DriverStatus.APPROVED, DriverStatus.SUSPENDED)


def _assert_submitted(driver):
    if driver.status not in REVIEWABLE_DRIVER_STATUSES:
        raise Conflict("The driver has not submitted this application for review yet.", code="application_not_submitted")


def review_document(document, approve, reviewer, note="", request=None):
    with transaction.atomic():
        document = DriverDocument.objects.select_for_update().select_related("driver").get(pk=document.pk)
        _assert_submitted(document.driver)
        if not approve and not note:
            raise BusinessRuleViolation("A rejection reason is required.", code="reason_required")
        document.status = ReviewStatus.APPROVED if approve else ReviewStatus.REJECTED
        document.review_note = note
        document.reviewed_by = reviewer
        document.reviewed_at = timezone.now()
        document.save(update_fields=["status", "review_note", "reviewed_by", "reviewed_at", "updated_at"])
        audit.record(
            "driver.document_reviewed", request=request, target=document, data={"approved": approve, "doc_type": document.doc_type}
        )
        _notify_driver(document.driver, "driver.document_reviewed", {"document_id": str(document.pk), "status": document.status})
    return document


def review_vehicle(vehicle, approve, reviewer, note="", request=None):
    with transaction.atomic():
        vehicle = Vehicle.objects.select_for_update().select_related("driver").get(pk=vehicle.pk)
        _assert_submitted(vehicle.driver)
        if not approve and not note:
            raise BusinessRuleViolation("A rejection reason is required.", code="reason_required")
        vehicle.status = ReviewStatus.APPROVED if approve else ReviewStatus.REJECTED
        vehicle.review_note = note
        vehicle.reviewed_by = reviewer
        vehicle.reviewed_at = timezone.now()
        vehicle.save(update_fields=["status", "review_note", "reviewed_by", "reviewed_at", "updated_at"])
        audit.record("driver.vehicle_reviewed", request=request, target=vehicle, data={"approved": approve})
        _notify_driver(vehicle.driver, "driver.vehicle_reviewed", {"vehicle_id": str(vehicle.pk), "status": vehicle.status})
    return vehicle


def review_driver(driver, decision, reviewer, note="", request=None):
    """decision: approve | reject | suspend | reinstate."""
    policy = current_policy()
    with transaction.atomic():
        driver = DriverProfile.objects.select_for_update().get(pk=driver.pk)
        allowed = {
            "approve": {DriverStatus.UNDER_REVIEW, DriverStatus.REJECTED},
            "reject": {DriverStatus.UNDER_REVIEW},
            "suspend": {DriverStatus.APPROVED},
            "reinstate": {DriverStatus.SUSPENDED},
        }
        if decision not in allowed:
            raise BusinessRuleViolation("Unknown decision.", code="invalid_decision")
        if driver.status not in allowed[decision]:
            raise Conflict(f"Cannot {decision} a driver who is {driver.status}.", code="invalid_transition")
        if decision in ("reject", "suspend") and not note:
            raise BusinessRuleViolation("A reason is required.", code="reason_required")
        if decision == "approve":
            missing = set(policy["drivers.required_documents"]) - _valid_documents(driver)
            if missing:
                raise BusinessRuleViolation({"unapproved_documents": sorted(missing)}, code="documents_not_approved")
            if not Vehicle.objects.filter(driver=driver, status=ReviewStatus.APPROVED, is_active=True).exists():
                raise BusinessRuleViolation("No approved vehicle.", code="vehicle_not_approved")
        driver.status = {
            "approve": DriverStatus.APPROVED,
            "reject": DriverStatus.REJECTED,
            "suspend": DriverStatus.SUSPENDED,
            "reinstate": DriverStatus.APPROVED,
        }[decision]
        if driver.status != DriverStatus.APPROVED:
            driver.is_online = False
        driver.review_note = note
        driver.reviewed_by = reviewer
        driver.reviewed_at = timezone.now()
        driver.save()
        audit.record(f"driver.{decision}", request=request, target=driver, data={"note": note})
        _notify_driver(driver, "driver.status_changed", {"status": driver.status})
    return driver


VEHICLE_DOCS = {DocumentType.VEHICLE_REGISTRATION, DocumentType.VEHICLE_PHOTO, DocumentType.INSURANCE}
