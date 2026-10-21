import math
from datetime import timedelta

from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.measure import D
from django.db import transaction
from django.utils import timezone

from apps.core.exceptions import BusinessRuleViolation

from .models import City, DriverLocation, ServiceArea

EARTH_RADIUS_M = 6371008.8


def haversine_m(a, b):
    """Great-circle distance in metres between two GEOS points (x=lng, y=lat)."""
    lat1, lng1, lat2, lng2 = map(math.radians, (a.y, a.x, b.y, b.x))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lng2 - lng1) / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


def fare_estimate(pickup, dropoff, policy):
    """Indicative range only (D004): 'estimate, not guaranteed'. Integer minor units, no floats stored."""
    distance_m = haversine_m(pickup, dropoff)
    mid = policy["fare.base_minor"] + int(round(policy["fare.per_km_minor"] * distance_m / 1000))
    spread = int(round(mid * policy["fare.range_pct"] / 100))
    return {
        "distance_m": int(round(distance_m)),
        "min_minor": max(0, mid - spread),
        "max_minor": mid + spread,
        "is_estimate": True,
        "label": "estimate, not guaranteed",
        "config_version": policy.version,
    }


def resolve_city(point, city_id=None):
    """Find the active city serving `point` within the current tenant, honouring service areas."""
    if city_id is not None:
        city = City.objects.filter(pk=city_id, is_active=True).first()
        if city is None:
            raise BusinessRuleViolation("Unknown or inactive city.", code="city_invalid")
        areas = ServiceArea.objects.filter(city=city, is_active=True)
        if areas.exists() and not areas.filter(area__contains=point).exists():
            raise BusinessRuleViolation("Pickup is outside the service area.", code="outside_service_area")
        return city
    area = ServiceArea.objects.filter(is_active=True, city__is_active=True, area__contains=point).select_related("city").first()
    if area is not None:
        return area.city
    city = City.objects.filter(is_active=True, boundary__contains=point).first()
    if city is None:
        raise BusinessRuleViolation("Pickup is outside every service area of this operator.", code="outside_service_area")
    return city


def update_driver_location(driver, point, accuracy_m, device_ts, heading=None, speed_mps=None):
    """Upserts presence. Out-of-order updates (older device timestamp) are ignored, never applied."""
    now = timezone.now()
    if device_ts > now + timedelta(minutes=2):
        device_ts = now  # untrusted device clock (clock skew); server time is authoritative
    with transaction.atomic():
        location = DriverLocation.objects.select_for_update().filter(driver=driver).first()
        if location is not None and location.device_ts >= device_ts:
            return location, False
        if location is None:
            location = DriverLocation(driver=driver)
        location.point = point
        location.accuracy_m = accuracy_m
        location.heading = heading
        location.speed_mps = speed_mps
        location.device_ts = device_ts
        location.server_ts = now
        location.save()
    return location, True


def nearby_driver_locations(point, radius_m, policy, exclude_driver_ids=(), limit=None):
    """Online, fresh-presence drivers within radius ordered by distance (tenant-scoped via manager + RLS)."""
    from apps.drivers.models import DriverStatus

    fresh_after = timezone.now() - timedelta(seconds=policy["presence.stale_seconds"])
    qs = (
        DriverLocation.objects.select_related("driver", "driver__user")
        .filter(
            driver__is_online=True,
            driver__status=DriverStatus.APPROVED,
            server_ts__gte=fresh_after,
            point__dwithin=(point, D(m=radius_m)),
        )
        .exclude(driver_id__in=list(exclude_driver_ids))
        .annotate(distance=Distance("point", point))
        .order_by("distance")
    )
    return qs[:limit] if limit else qs
