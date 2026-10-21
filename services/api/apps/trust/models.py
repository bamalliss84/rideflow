"""Ratings, trust scores, conduct incidents, enforcement, disputes and appeals — all per tenant (OD-02 default)."""

from django.conf import settings
from django.db import models
from django.db.models import Q

from apps.core.models import TenantScopedModel


class Rating(TenantScopedModel):
    ride = models.ForeignKey("rides.Ride", on_delete=models.PROTECT, related_name="ratings")
    rater = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    ratee = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    rater_role = models.CharField(max_length=16)
    ratee_role = models.CharField(max_length=16)
    stars = models.PositiveSmallIntegerField()
    tags = models.JSONField(default=list, blank=True)
    comment = models.CharField(max_length=500, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["ride", "rater"], name="one_rating_per_rater_per_ride"),
            models.CheckConstraint(condition=Q(stars__gte=1) & Q(stars__lte=5), name="stars_1_to_5"),
        ]
        indexes = [models.Index(fields=["tenant", "ratee", "ratee_role"])]


class TrustSnapshot(TenantScopedModel):
    """Latest computed trust profile of a user in one role. Display only; never a sanction by itself."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    role = models.CharField(max_length=16)
    score = models.FloatField()
    rating_avg = models.FloatField()
    rating_count = models.PositiveIntegerField()
    completed_rides = models.PositiveIntegerField()
    completion_rate = models.FloatField(null=True)
    tier = models.CharField(max_length=16)
    components = models.JSONField(default=dict)
    method_version = models.CharField(max_length=40)
    config_version = models.PositiveIntegerField(default=0)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["tenant", "user", "role"], name="uniq_trust_snapshot")]


class ViolationStatus(models.TextChoices):
    PENDING_REVIEW = "pending_review", "Pending human review"
    VERIFIED = "verified", "Verified"
    DISMISSED = "dismissed", "Dismissed"
    OVERTURNED = "overturned", "Overturned on appeal"


class ViolationKind(models.TextChoices):
    RIDER_NO_SHOW = "rider_no_show", "Rider no-show"
    RIDER_LATE_CANCELLATION = "rider_late_cancellation", "Rider late cancellation"
    DRIVER_LATE_CANCELLATION = "driver_late_cancellation", "Driver late cancellation / abandonment"
    DRIVER_NO_ARRIVAL = "driver_no_arrival", "Driver did not arrive"
    COMPLAINT_UPHELD = "complaint_upheld", "Complaint upheld"
    PRICE_NON_COMPLIANCE = "price_non_compliance", "Agreed price not honoured"
    SAFETY = "safety", "Safety incident"


class Violation(TenantScopedModel):
    subject = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    subject_role = models.CharField(max_length=16)
    kind = models.CharField(max_length=32, choices=ViolationKind.choices)
    ride = models.ForeignKey("rides.Ride", null=True, blank=True, on_delete=models.PROTECT, related_name="violations")
    dispute = models.ForeignKey("trust.Dispute", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    status = models.CharField(max_length=16, choices=ViolationStatus.choices, default=ViolationStatus.PENDING_REVIEW)
    evidence = models.JSONField(default=dict, blank=True)
    reported_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    reviewed_at = models.DateTimeField(null=True, blank=True)
    review_note = models.CharField(max_length=500, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["tenant", "subject", "status", "reviewed_at"])]


class EnforcementType(models.TextChoices):
    WARNING = "warning", "Warning"
    COMMITMENT_EFFECT = "commitment_effect", "Commitment score effect"
    RESTRICTION = "restriction", "Temporary restriction"
    ESCALATION = "escalation", "Human escalation (safety)"


class EnforcementStatus(models.TextChoices):
    PROPOSED = "proposed", "Proposed (needs human activation)"
    ACTIVE = "active", "Active"
    REVOKED = "revoked", "Revoked"


class EnforcementAction(TenantScopedModel):
    subject = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    subject_role = models.CharField(max_length=16)
    violation = models.ForeignKey(Violation, on_delete=models.PROTECT, related_name="enforcement_actions")
    level = models.PositiveSmallIntegerField()
    action_type = models.CharField(max_length=20, choices=EnforcementType.choices)
    status = models.CharField(max_length=16, choices=EnforcementStatus.choices)
    duration_hours = models.PositiveIntegerField(default=0)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)
    reason = models.CharField(max_length=500, blank=True)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["tenant", "subject", "status", "ends_at"])]


class DisputeStatus(models.TextChoices):
    OPEN = "open", "Open"
    UNDER_REVIEW = "under_review", "Under review"
    UPHELD = "upheld", "Upheld"
    REJECTED = "rejected", "Rejected"


class DisputeCategory(models.TextChoices):
    FARE = "fare", "Fare / agreed price"
    BEHAVIOR = "behavior", "Behaviour / complaint"
    SAFETY = "safety", "Safety"
    NO_SHOW_CONTEST = "no_show_contest", "Contest a no-show"
    CANCELLATION = "cancellation", "Cancellation"
    OTHER = "other", "Other"


class Dispute(TenantScopedModel):
    ride = models.ForeignKey("rides.Ride", on_delete=models.PROTECT, related_name="disputes")
    opened_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    opened_by_role = models.CharField(max_length=16)
    against = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    against_role = models.CharField(max_length=16, blank=True)
    category = models.CharField(max_length=20, choices=DisputeCategory.choices)
    description = models.TextField(max_length=2000)
    is_safety = models.BooleanField(default=False)
    status = models.CharField(max_length=16, choices=DisputeStatus.choices, default=DisputeStatus.OPEN)
    assigned_to = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    resolution_note = models.CharField(max_length=1000, blank=True)
    resolved_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["ride", "opened_by"],
                condition=Q(status__in=["open", "under_review"]),
                name="one_open_dispute_per_party_per_ride",
            ),
        ]
        indexes = [models.Index(fields=["tenant", "status", "created_at"])]


class DisputeNote(TenantScopedModel):
    """Evidence statements with provenance (author + server time); append-only by API."""

    dispute = models.ForeignKey(Dispute, on_delete=models.PROTECT, related_name="notes")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    author_role = models.CharField(max_length=16)
    note = models.TextField(max_length=2000)

    class Meta:
        ordering = ["created_at"]


class AppealStatus(models.TextChoices):
    PENDING = "pending", "Pending"
    UPHELD = "upheld", "Upheld (violation overturned)"
    REJECTED = "rejected", "Rejected"


class Appeal(TenantScopedModel):
    violation = models.ForeignKey(Violation, on_delete=models.PROTECT, related_name="appeals")
    appellant = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    reason = models.TextField(max_length=2000)
    status = models.CharField(max_length=16, choices=AppealStatus.choices, default=AppealStatus.PENDING)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    decided_at = models.DateTimeField(null=True, blank=True)
    decision_note = models.CharField(max_length=1000, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["violation"], condition=Q(status="pending"), name="one_pending_appeal"),
        ]
