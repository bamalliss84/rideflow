from rest_framework import serializers

from apps.core.fields import PointField
from apps.tenancy.policy import current_policy

from . import state_machine as sm
from .models import ACTIVE_CONTACT_STATUSES, Bid, RideAmendment, RideEvent, TripShare

CANCEL_REASON_CODES = [
    "changed_mind",
    "driver_too_far",
    "driver_asked",
    "wait_too_long",
    "rider_asked",
    "car_problem",
    "wrong_pickup",
    "other",
]

COARSE = 3  # ~110 m


# ----------------------------------------------------------------- inputs


class RideCreateSerializer(serializers.Serializer):
    city_id = serializers.UUIDField(required=False, allow_null=True)
    pickup = PointField()
    pickup_landmark = serializers.CharField(max_length=200)
    dropoff = PointField()
    dropoff_landmark = serializers.CharField(max_length=200)
    rider_note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
    pickup_note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
    dropoff_note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
    rider_price_minor = serializers.IntegerField(min_value=1, required=False, allow_null=True)
    require_start_code = serializers.BooleanField(required=False, default=False)


class VersionSerializer(serializers.Serializer):
    expected_version = serializers.IntegerField(min_value=1)


class StartSerializer(VersionSerializer):
    start_code = serializers.CharField(max_length=4, required=False, allow_blank=True, default="")


class RaisePriceSerializer(VersionSerializer):
    amount_minor = serializers.IntegerField(min_value=1)


class EmergencySerializer(serializers.Serializer):
    location = PointField(required=False, allow_null=True, default=None)


class EmergencyResponseSerializer(serializers.Serializer):
    recorded = serializers.BooleanField()
    emergency_phone = serializers.CharField(allow_null=True)


class TripShareSerializer(serializers.Serializer):
    token = serializers.CharField()
    url = serializers.CharField(allow_null=True)


class DriverPositionSerializer(serializers.Serializer):
    lat = serializers.FloatField()
    lng = serializers.FloatField()
    heading = serializers.FloatField(allow_null=True)
    age_seconds = serializers.IntegerField()
    stale = serializers.BooleanField()


class OptionalVersionSerializer(serializers.Serializer):
    expected_version = serializers.IntegerField(min_value=1, required=False, allow_null=True)


class SelectBidSerializer(VersionSerializer):
    bid_id = serializers.UUIDField()


class CancelSerializer(VersionSerializer):
    reason = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
    reason_code = serializers.ChoiceField(choices=CANCEL_REASON_CODES, required=False, allow_blank=True, default="")


class DeclineSerializer(CancelSerializer):
    pass


class ArriveSerializer(VersionSerializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    accuracy_m = serializers.FloatField(min_value=0, max_value=10000)
    device_ts = serializers.DateTimeField(required=False, allow_null=True)


class ContactAttemptSerializer(serializers.Serializer):
    method = serializers.ChoiceField(choices=["call", "sms", "in_app"])


class BidCreateSerializer(serializers.Serializer):
    amount_minor = serializers.IntegerField(min_value=1, max_value=10**12)
    eta_seconds = serializers.IntegerField(min_value=0, max_value=7200)


class AmendmentCreateSerializer(serializers.Serializer):
    new_fare_minor = serializers.IntegerField(min_value=1, max_value=10**12)
    reason = serializers.CharField(max_length=300)
    new_dropoff = PointField(required=False, allow_null=True)
    new_dropoff_landmark = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")


class AmendmentRespondSerializer(serializers.Serializer):
    accept = serializers.BooleanField()


class EventsQuerySerializer(serializers.Serializer):
    after_seq = serializers.IntegerField(min_value=0, required=False, default=0)


# ----------------------------------------------------------------- outputs


class TrustBriefSerializer(serializers.Serializer):
    rating_avg = serializers.FloatField()
    rating_count = serializers.IntegerField()
    completed_rides = serializers.IntegerField()
    completion_rate = serializers.FloatField(allow_null=True)
    tier = serializers.CharField()
    rating_provisional = serializers.BooleanField()


class VehicleBriefSerializer(serializers.Serializer):
    make = serializers.CharField()
    model = serializers.CharField()
    color = serializers.CharField()
    plate_number = serializers.CharField(allow_null=True)


class PartyBriefSerializer(serializers.Serializer):
    user_id = serializers.UUIDField()
    driver_id = serializers.UUIDField(allow_null=True, required=False)
    display_name = serializers.CharField()
    phone = serializers.CharField(allow_null=True)
    verified = serializers.BooleanField()
    trust = TrustBriefSerializer()
    vehicle = VehicleBriefSerializer(allow_null=True, required=False)


def _first_name(user):
    name = (user.full_name or "").strip()
    return name.split()[0] if name else "—"


def _vehicle(driver, include_plate):
    vehicle = driver.vehicles.filter(status="approved", is_active=True).order_by("-created_at").first() if driver else None
    if vehicle is None:
        return None
    return {
        "make": vehicle.make,
        "model": vehicle.model,
        "color": vehicle.color,
        "plate_number": vehicle.plate_number if include_plate else None,
    }


def _public_trust(summary):
    """Below the minimum sample the average is only the smoothing prior, so apps show "new" instead of a number."""
    trust = {k: summary[k] for k in ("rating_avg", "rating_count", "completed_rides", "completion_rate", "tier")}
    trust["rating_provisional"] = summary["rating_count"] < current_policy()["trust.min_sample"]
    return trust


def driver_brief(driver, *, include_contact=False, include_plate=False):
    from apps.trust.services import public_summary

    summary = public_summary(driver.user, "driver")
    return {
        "user_id": driver.user_id,
        "driver_id": driver.pk,
        "display_name": _first_name(driver.user),
        "phone": driver.user.phone if include_contact else None,
        "verified": driver.status == "approved",
        "trust": _public_trust(summary),
        "vehicle": _vehicle(driver, include_plate),
    }


def rider_brief(user, *, include_contact=False):
    from apps.trust.services import public_summary

    summary = public_summary(user, "rider")
    return {
        "user_id": user.pk,
        "driver_id": None,
        "display_name": _first_name(user),
        "phone": user.phone if include_contact else None,
        "verified": True,
        "trust": _public_trust(summary),
        "vehicle": None,
    }


class BidSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    amount_minor = serializers.IntegerField()
    currency = serializers.CharField()
    eta_seconds = serializers.IntegerField()
    expires_at = serializers.DateTimeField()
    status = serializers.CharField()
    created_at = serializers.DateTimeField()
    driver = PartyBriefSerializer(required=False)

    def to_representation(self, bid):
        data = {
            "id": bid.pk,
            "amount_minor": bid.amount_minor,
            "currency": bid.currency,
            "eta_seconds": bid.eta_seconds,
            "expires_at": bid.expires_at,
            "status": bid.status,
            "created_at": bid.created_at,
        }
        if self.context.get("with_driver"):
            data["driver"] = driver_brief(bid.driver)
        return _jsonable_deep(data)


class EstimateSerializer(serializers.Serializer):
    min_minor = serializers.IntegerField()
    max_minor = serializers.IntegerField()
    distance_m = serializers.IntegerField()
    label = serializers.CharField()
    bid_step_minor = serializers.IntegerField()


class MyRatingSerializer(serializers.Serializer):
    stars = serializers.IntegerField()
    tags = serializers.ListField(child=serializers.CharField())


def _my_rating(ride, user):
    if ride.completed_at is None:
        return None
    return ride.ratings.filter(rater=user).values("stars", "tags").first()


class HiddenOffersSerializer(serializers.Serializer):
    count = serializers.IntegerField()


class RideSerializer(serializers.Serializer):
    """Viewer-dependent ride snapshot. Candidate drivers see coarse locations and no contact data (T12)."""

    id = serializers.UUIDField()
    status = serializers.CharField()
    version = serializers.IntegerField()
    event_seq = serializers.IntegerField()
    viewer_role = serializers.CharField()
    allowed_actions = serializers.ListField(child=serializers.CharField())
    city_id = serializers.UUIDField()
    pickup = PointField()
    pickup_landmark = serializers.CharField()
    dropoff = PointField()
    dropoff_landmark = serializers.CharField()
    rider_note = serializers.CharField()
    pickup_note = serializers.CharField()
    dropoff_note = serializers.CharField()
    currency = serializers.CharField()
    estimate = EstimateSerializer()
    rider_price_minor = serializers.IntegerField(allow_null=True)
    my_rating = MyRatingSerializer(allow_null=True)
    agreed_fare_minor = serializers.IntegerField(allow_null=True)
    price_locked_at = serializers.DateTimeField(allow_null=True)
    match_deadline = serializers.DateTimeField(allow_null=True)
    open_bid_count = serializers.IntegerField(allow_null=True)
    my_bid = BidSerializer(allow_null=True)
    driver = PartyBriefSerializer(allow_null=True)
    rider = PartyBriefSerializer(allow_null=True)
    timestamps = serializers.DictField(child=serializers.DateTimeField(allow_null=True))
    arrival = serializers.DictField(allow_null=True)
    cancellation = serializers.DictField(allow_null=True)
    cash = serializers.DictField(allow_null=True)
    no_show = serializers.DictField(allow_null=True)
    free_cancel_until = serializers.DateTimeField(allow_null=True)
    start_code_required = serializers.BooleanField()
    start_code = serializers.CharField(allow_null=True)
    emergency_phone = serializers.CharField(allow_null=True)
    share_active = serializers.BooleanField(allow_null=True)
    config_version = serializers.IntegerField()

    def to_representation(self, ride):
        user = self.context["request"].user
        if ride.rider_id == user.pk:
            viewer = "rider"
        elif ride.driver_id and ride.driver.user_id == user.pk:
            viewer = "driver"
        else:
            viewer = "candidate"
        exact = viewer in ("rider", "driver")
        contact = exact and ride.status in ACTIVE_CONTACT_STATUSES
        point = PointField(precision=None if exact else COARSE)
        open_bids = None
        my_bid = None
        if viewer == "rider":
            from .services import open_bids as _open

            open_bids = _open(ride).count()
        if viewer in ("driver", "candidate"):
            bid = Bid.objects.filter(ride=ride, driver__user=user).order_by("-created_at").first()
            my_bid = BidSerializer(bid).data if bid else None
        actor = "rider" if viewer == "rider" else "driver"
        data = {
            "id": str(ride.pk),
            "status": ride.status,
            "version": ride.version,
            "event_seq": ride.event_seq,
            "viewer_role": viewer,
            "allowed_actions": sm.allowed_actions(ride.status, actor)
            if viewer != "candidate"
            else (["bid"] if ride.status == "bidding" else []),
            "city_id": str(ride.city_id),
            "pickup": point.to_representation(ride.pickup),
            "pickup_landmark": ride.pickup_landmark,
            "dropoff": point.to_representation(ride.dropoff),
            "dropoff_landmark": ride.dropoff_landmark,
            "rider_note": ride.rider_note if exact else "",
            "pickup_note": ride.pickup_note if exact else "",
            "dropoff_note": ride.dropoff_note if exact else "",
            "currency": ride.currency,
            "estimate": {
                "min_minor": ride.estimate_min_minor,
                "max_minor": ride.estimate_max_minor,
                "distance_m": ride.estimated_distance_m,
                "label": "estimate, not guaranteed",
                "bid_step_minor": current_policy()["fare.bid_step_minor"],
            },
            "rider_price_minor": ride.rider_price_minor,
            "my_rating": _my_rating(ride, user) if viewer != "candidate" else None,
            "agreed_fare_minor": ride.agreed_fare_minor,
            "price_locked_at": ride.price_locked_at,
            "match_deadline": ride.match_deadline,
            "open_bid_count": open_bids,
            "my_bid": my_bid,
            "driver": driver_brief(ride.driver, include_contact=contact, include_plate=True)
            if viewer == "rider" and ride.driver_id and ride.status != "match_pending"
            else None,
            "rider": rider_brief(ride.rider, include_contact=contact and viewer == "driver") if viewer != "rider" else None,
            "timestamps": {
                f: getattr(ride, f)
                for f in (
                    "created_at",
                    "bidding_at",
                    "selected_at",
                    "assigned_at",
                    "en_route_at",
                    "arrived_at",
                    "started_at",
                    "completed_at",
                    "cancelled_at",
                )
            },
            "arrival": {
                "distance_m": ride.arrival_distance_m,
                "accuracy_m": ride.arrival_accuracy_m,
                "within_geofence": ride.arrival_within_geofence,
            }
            if ride.arrived_at and exact
            else None,
            "cancellation": {
                "by_role": ride.cancelled_by_role,
                "reason": ride.cancel_reason,
                "reason_code": ride.cancel_reason_code,
                "late": ride.cancellation_late,
            }
            if ride.cancelled_at
            else None,
            "cash": {
                "amount_minor": ride.cash_amount_minor,
                "driver_confirmed_at": ride.cash_driver_confirmed_at,
                "rider_confirmed_at": ride.cash_rider_confirmed_at,
            }
            if ride.completed_at and exact
            else None,
            "no_show": _no_show_state(ride) if viewer == "driver" and ride.status == "arrived" else None,
            "free_cancel_until": _free_cancel_until(ride) if exact else None,
            "start_code_required": ride.start_code_required if exact else False,
            "start_code": ride.start_code
            if viewer == "rider" and ride.start_code_required and ride.status in ("assigned", "en_route", "arrived")
            else None,
            "emergency_phone": _emergency_phone() if contact else None,
            "share_active": TripShare.objects.filter(ride=ride, revoked_at__isnull=True).exists() if viewer == "rider" else None,
            "config_version": ride.config_version,
        }
        return _jsonable_deep(data)


def _free_cancel_until(ride):
    from .services import free_cancel_until

    return free_cancel_until(ride, current_policy())


def _emergency_phone():
    return current_policy()["safety.emergency_phone"] or None


def _no_show_state(ride):
    """What the driver app needs to explain when a no-show can be reported; `mark_no_show` still decides."""
    policy = current_policy()
    return {
        "wait_seconds": policy["noshow.min_wait_seconds"],
        "contact_required": policy["noshow.require_contact_attempt"],
        "contact_attempts": RideEvent.objects.filter(ride=ride, event_type="contact_attempt", created_at__gte=ride.arrived_at).count(),
    }


def _jsonable_deep(value):
    if isinstance(value, dict):
        return {k: _jsonable_deep(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jsonable_deep(v) for v in value]
    if hasattr(value, "isoformat"):
        return value.isoformat().replace("+00:00", "Z")
    if value.__class__.__name__ == "UUID":
        return str(value)
    return value


class PublicTripSerializer(serializers.Serializer):
    status = serializers.CharField()
    active = serializers.BooleanField()
    dropoff_landmark = serializers.CharField(allow_null=True)
    driver_name = serializers.CharField(allow_null=True)
    vehicle = VehicleBriefSerializer(allow_null=True)
    position = DriverPositionSerializer(allow_null=True)


def public_trip_data(ride, position):
    if ride.status not in ACTIVE_CONTACT_STATUSES:
        return {
            "status": ride.status,
            "active": False,
            "dropoff_landmark": None,
            "driver_name": None,
            "vehicle": None,
            "position": None,
        }
    return {
        "status": ride.status,
        "active": True,
        "dropoff_landmark": ride.dropoff_landmark,
        "driver_name": _first_name(ride.driver.user),
        "vehicle": _vehicle(ride.driver, True),
        "position": position,
    }


class RideEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = RideEvent
        fields = ["seq", "event_type", "actor_role", "from_status", "to_status", "data", "device_ts", "created_at"]
        read_only_fields = fields


class AmendmentSerializer(serializers.ModelSerializer):
    new_dropoff = PointField(allow_null=True)

    class Meta:
        model = RideAmendment
        fields = [
            "id",
            "proposed_by_role",
            "new_fare_minor",
            "new_dropoff",
            "new_dropoff_landmark",
            "reason",
            "status",
            "responded_at",
            "created_at",
        ]
        read_only_fields = fields


class AdminRideSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()
    rider_name = serializers.CharField(source="rider.full_name", read_only=True)
    rider_phone = serializers.CharField(source="rider.phone", read_only=True)
    driver_name = serializers.CharField(source="driver.user.full_name", read_only=True, allow_null=True)
    driver_phone = serializers.CharField(source="driver.user.phone", read_only=True, allow_null=True)
    city_name = serializers.CharField(source="city.name", read_only=True)
    estimated_distance_m = serializers.IntegerField()
    rider_price_minor = serializers.IntegerField(allow_null=True)
    cash_driver_confirmed_at = serializers.DateTimeField(allow_null=True)
    cash_rider_confirmed_at = serializers.DateTimeField(allow_null=True)
    arrived_at = serializers.DateTimeField(allow_null=True)
    started_at = serializers.DateTimeField(allow_null=True)
    version = serializers.IntegerField()
    city_id = serializers.UUIDField()
    rider_id = serializers.UUIDField()
    driver_id = serializers.UUIDField(allow_null=True)
    pickup = PointField()
    pickup_landmark = serializers.CharField()
    dropoff = PointField()
    dropoff_landmark = serializers.CharField()
    currency = serializers.CharField()
    estimate_min_minor = serializers.IntegerField()
    estimate_max_minor = serializers.IntegerField()
    agreed_fare_minor = serializers.IntegerField(allow_null=True)
    wave_count = serializers.IntegerField()
    cancelled_by_role = serializers.CharField()
    cancel_reason = serializers.CharField()
    cancellation_late = serializers.BooleanField(allow_null=True)
    arrival_within_geofence = serializers.BooleanField(allow_null=True)
    no_show_evidence = serializers.JSONField(allow_null=True)
    config_version = serializers.IntegerField()
    created_at = serializers.DateTimeField()
    assigned_at = serializers.DateTimeField(allow_null=True)
    completed_at = serializers.DateTimeField(allow_null=True)
    cancelled_at = serializers.DateTimeField(allow_null=True)
