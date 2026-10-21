from django.conf import settings
from django.db import models

from apps.core.files import tenant_upload_to
from apps.core.models import TenantScopedModel


class DriverStatus(models.TextChoices):
    PENDING_DOCUMENTS = "pending_documents", "Pending documents"
    UNDER_REVIEW = "under_review", "Under review"
    APPROVED = "approved", "Approved"
    REJECTED = "rejected", "Rejected"
    SUSPENDED = "suspended", "Suspended"


class ReviewStatus(models.TextChoices):
    PENDING = "pending", "Pending"
    APPROVED = "approved", "Approved"
    REJECTED = "rejected", "Rejected"


class DocumentType(models.TextChoices):
    NATIONAL_ID = "national_id", "National ID"
    DRIVING_LICENSE = "driving_license", "Driving license"
    VEHICLE_REGISTRATION = "vehicle_registration", "Vehicle registration"
    VEHICLE_PHOTO = "vehicle_photo", "Vehicle photo"
    DRIVER_PHOTO = "driver_photo", "Driver photo"
    INSURANCE = "insurance", "Insurance"


VEHICLE_DOCUMENT_TYPES = {DocumentType.VEHICLE_REGISTRATION, DocumentType.VEHICLE_PHOTO, DocumentType.INSURANCE}


class DriverProfile(TenantScopedModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="driver_profiles")
    status = models.CharField(max_length=24, choices=DriverStatus.choices, default=DriverStatus.PENDING_DOCUMENTS)
    is_online = models.BooleanField(default=False)
    online_since = models.DateTimeField(null=True, blank=True)
    review_note = models.CharField(max_length=500, blank=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    reviewed_at = models.DateTimeField(null=True, blank=True)
    submitted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["tenant", "user"], name="uniq_driver_profile_per_tenant")]
        indexes = [models.Index(fields=["tenant", "status", "is_online"])]

    def __str__(self):
        return f"Driver {self.user_id}"


class Vehicle(TenantScopedModel):
    driver = models.ForeignKey(DriverProfile, on_delete=models.PROTECT, related_name="vehicles")
    plate_number = models.CharField(max_length=20)
    make = models.CharField(max_length=60)
    model = models.CharField(max_length=60)
    color = models.CharField(max_length=40)
    year = models.PositiveSmallIntegerField(null=True, blank=True)
    seats = models.PositiveSmallIntegerField(default=4)
    status = models.CharField(max_length=16, choices=ReviewStatus.choices, default=ReviewStatus.PENDING)
    is_active = models.BooleanField(default=True)
    review_note = models.CharField(max_length=500, blank=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["tenant", "plate_number"], name="uniq_plate_per_tenant")]


class DriverDocument(TenantScopedModel):
    driver = models.ForeignKey(DriverProfile, on_delete=models.PROTECT, related_name="documents")
    vehicle = models.ForeignKey(Vehicle, null=True, blank=True, on_delete=models.PROTECT, related_name="documents")
    doc_type = models.CharField(max_length=32, choices=DocumentType.choices)
    number = models.CharField(max_length=64, blank=True)
    expires_at = models.DateField(null=True, blank=True)
    file = models.FileField(upload_to=tenant_upload_to("driver-documents"), max_length=255)
    content_type = models.CharField(max_length=64)
    sha256 = models.CharField(max_length=64)
    status = models.CharField(max_length=16, choices=ReviewStatus.choices, default=ReviewStatus.PENDING)
    review_note = models.CharField(max_length=500, blank=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["tenant", "status"])]
