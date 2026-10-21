"""Ride aggregate: request -> bids -> match -> trip, one row per ride with an explicit state machine.

Phase 1 decision: RideRequest, Match and Trip from DATA_MODEL.md are unified in one `Ride` aggregate so that
every state change is a single-row, version-checked, row-locked update. Bids, dispatch candidates, events,
location evidence and amendments are separate tables.
"""

from django.conf import settings
from django.contrib.gis.db import models
from django.db.models import Q

from apps.core.models import AppendOnlyMixin, TenantScopedModel


class RideStatus(models.TextChoices):
    REQUESTED = "requested", "Requested"
    BIDDING = "bidding", "Bidding"
    MATCH_PENDING = "match_pending", "Awaiting driver confirmation"
    ASSIGNED = "assigned", "Assigned"
    EN_ROUTE = "en_route", "Driver en route"
    ARRIVED = "arrived", "Driver arrived"
    IN_PROGRESS = "in_progress", "In progress"
    COMPLETED = "completed", "Completed"
    CANCELLED = "cancelled", "Cancelled"
    NO_SHOW = "no_show", "Rider no-show"
    DISPUTED = "disputed", "Disputed"


RIDER_ACTIVE_STATUSES = [
    RideStatus.REQUESTED,
    RideStatus.BIDDING,
    RideStatus.MATCH_PENDING,
    RideStatus.ASSIGNED,
    RideStatus.EN_ROUTE,
    RideStatus.ARRIVED,
    RideStatus.IN_PROGRESS,
]
DRIVER_ACTIVE_STATUSES = [
    RideStatus.MATCH_PENDING,
    RideStatus.ASSIGNED,
    RideStatus.EN_ROUTE,
    RideStatus.ARRIVED,
    RideStatus.IN_PROGRESS,
]
ACTIVE_CONTACT_STATUSES = [RideStatus.ASSIGNED, RideStatus.EN_ROUTE, RideStatus.ARRIVED, RideStatus.IN_PROGRESS]
TERMINAL_STATUSES = [RideStatus.COMPLETED, RideStatus.CANCELLED, RideStatus.NO_SHOW, RideStatus.DISPUTED]


class Ride(TenantScopedModel):
    rider = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="rides_as_rider")
    city = models.ForeignKey("geo.City", on_delete=models.PROTECT, related_name="rides")
    pickup = models.PointField(srid=4326)
    pickup_landmark = models.CharField(max_length=200)
    dropoff = models.PointField(srid=4326)
    dropoff_landmark = models.CharField(max_length=200)
    rider_note = models.CharField(max_length=300, blank=True)

    status = models.CharField(max_length=16, choices=RideStatus.choices, default=RideStatus.REQUESTED)
    version = models.PositiveIntegerField(default=1)
    event_seq = models.PositiveIntegerField(default=0)
    config_version = models.PositiveIntegerField(default=0)

    currency = models.CharField(max_length=3)
    estimate_min_minor = models.BigIntegerField()
    estimate_max_minor = models.BigIntegerField()
    estimated_distance_m = models.PositiveIntegerField()

    wave_count = models.PositiveSmallIntegerField(default=0)
    dispatch_radius_m = models.PositiveIntegerField(default=0)

    driver = models.ForeignKey("drivers.DriverProfile", null=True, blank=True, on_delete=models.PROTECT, related_name="rides")
    selected_bid = models.ForeignKey("rides.Bid", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    match_deadline = models.DateTimeField(null=True, blank=True)
    agreed_fare_minor = models.BigIntegerField(null=True, blank=True)
    price_locked_at = models.DateTimeField(null=True, blank=True)

    bidding_at = models.DateTimeField(null=True, blank=True)
    selected_at = models.DateTimeField(null=True, blank=True)
    assigned_at = models.DateTimeField(null=True, blank=True)
    en_route_at = models.DateTimeField(null=True, blank=True)
    arrived_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)

    arrival_distance_m = models.PositiveIntegerField(null=True, blank=True)
    arrival_accuracy_m = models.FloatField(null=True, blank=True)
    arrival_within_geofence = models.BooleanField(null=True, blank=True)

    cancelled_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    cancelled_by_role = models.CharField(max_length=16, blank=True)
    cancel_reason = models.CharField(max_length=300, blank=True)
    cancellation_late = models.BooleanField(null=True, blank=True)
    no_show_evidence = models.JSONField(null=True, blank=True)

    cash_amount_minor = models.BigIntegerField(null=True, blank=True)
    cash_driver_confirmed_at = models.DateTimeField(null=True, blank=True)
    cash_rider_confirmed_at = models.DateTimeField(null=True, blank=True)
    status_before_dispute = models.CharField(max_length=16, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["tenant", "driver"], condition=Q(status__in=DRIVER_ACTIVE_STATUSES), name="one_active_ride_per_driver"
            ),
            models.UniqueConstraint(
                fields=["tenant", "rider"], condition=Q(status__in=RIDER_ACTIVE_STATUSES), name="one_active_ride_per_rider"
            ),
            models.CheckConstraint(
                condition=Q(agreed_fare_minor__isnull=True) | Q(agreed_fare_minor__gt=0), name="agreed_fare_positive"
            ),
        ]
        indexes = [
            models.Index(fields=["tenant", "status", "created_at"]),
            models.Index(fields=["tenant", "rider", "created_at"]),
            models.Index(fields=["tenant", "driver", "created_at"]),
        ]


class BidStatus(models.TextChoices):
    OPEN = "open", "Open"
    WITHDRAWN = "withdrawn", "Withdrawn"
    EXPIRED = "expired", "Expired"
    SELECTED = "selected", "Selected by rider"
    ACCEPTED = "accepted", "Confirmed by driver"
    DECLINED = "declined", "Declined by driver"
    LOST = "lost", "Not selected"


class Bid(TenantScopedModel):
    ride = models.ForeignKey(Ride, on_delete=models.PROTECT, related_name="bids")
    driver = models.ForeignKey("drivers.DriverProfile", on_delete=models.PROTECT, related_name="bids")
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    eta_seconds = models.PositiveIntegerField()
    expires_at = models.DateTimeField()
    status = models.CharField(max_length=16, choices=BidStatus.choices, default=BidStatus.OPEN)

    class Meta:
        ordering = ["amount_minor", "created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["ride", "driver"], condition=Q(status__in=["open", "selected"]), name="one_live_bid_per_driver_per_ride"
            ),
            models.CheckConstraint(condition=Q(amount_minor__gt=0), name="bid_amount_positive"),
        ]
        indexes = [models.Index(fields=["tenant", "ride", "status"]), models.Index(fields=["tenant", "driver", "status"])]


class DispatchCandidate(TenantScopedModel):
    ride = models.ForeignKey(Ride, on_delete=models.PROTECT, related_name="candidates")
    driver = models.ForeignKey("drivers.DriverProfile", on_delete=models.PROTECT, related_name="dispatches")
    wave = models.PositiveSmallIntegerField()
    distance_m = models.PositiveIntegerField()

    class Meta:
        constraints = [models.UniqueConstraint(fields=["ride", "driver"], name="uniq_dispatch_candidate")]


class RideEvent(AppendOnlyMixin, TenantScopedModel):
    """Ordered, immutable ride history; `seq` is the replay cursor clients use after reconnecting."""

    ride = models.ForeignKey(Ride, on_delete=models.PROTECT, related_name="events")
    seq = models.PositiveIntegerField()
    event_type = models.CharField(max_length=40)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    actor_role = models.CharField(max_length=16)
    from_status = models.CharField(max_length=16, blank=True)
    to_status = models.CharField(max_length=16, blank=True)
    data = models.JSONField(default=dict, blank=True)
    device_ts = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["seq"]
        constraints = [models.UniqueConstraint(fields=["ride", "seq"], name="uniq_ride_event_seq")]


class EvidenceKind(models.TextChoices):
    PING = "ping", "Location ping"
    ARRIVAL = "arrival", "Arrival"
    START = "start", "Trip start"
    COMPLETE = "complete", "Trip end"


class LocationEvidence(AppendOnlyMixin, TenantScopedModel):
    ride = models.ForeignKey(Ride, on_delete=models.PROTECT, related_name="location_evidence")
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    kind = models.CharField(max_length=16, choices=EvidenceKind.choices)
    point = models.PointField(srid=4326)
    accuracy_m = models.FloatField()
    device_ts = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["created_at"]


class AmendmentStatus(models.TextChoices):
    PENDING = "pending", "Pending"
    ACCEPTED = "accepted", "Accepted"
    REJECTED = "rejected", "Rejected"


class RideAmendment(TenantScopedModel):
    """Bilateral price/destination change after match (price is otherwise immutable, T14)."""

    ride = models.ForeignKey(Ride, on_delete=models.PROTECT, related_name="amendments")
    proposed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    proposed_by_role = models.CharField(max_length=16)
    new_fare_minor = models.BigIntegerField()
    new_dropoff = models.PointField(srid=4326, null=True, blank=True)
    new_dropoff_landmark = models.CharField(max_length=200, blank=True)
    reason = models.CharField(max_length=300)
    status = models.CharField(max_length=16, choices=AmendmentStatus.choices, default=AmendmentStatus.PENDING)
    responded_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["ride"], condition=Q(status="pending"), name="one_pending_amendment"),
            models.CheckConstraint(condition=Q(new_fare_minor__gt=0), name="amendment_fare_positive"),
        ]
