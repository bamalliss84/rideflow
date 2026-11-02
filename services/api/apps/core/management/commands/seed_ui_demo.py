"""Local UI review data: open requests for one online driver, from riders with and without ratings.

Run again for fresh requests (they expire with `rides.bidding_timeout_seconds`). The driver must be online
with a fresh location near the city, or dispatch would skip them. Refuses to run outside local development.
"""

from datetime import timedelta

from django.conf import settings
from django.contrib.gis.geos import Point
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from rest_framework.exceptions import APIException

from apps.core.context import system_context, tenant_context
from apps.drivers import services as driver_services
from apps.drivers.models import DriverProfile
from apps.geo.models import City
from apps.geo.services import fare_estimate
from apps.rides import services as ride_services
from apps.rides import state_machine as sm
from apps.rides.models import DispatchCandidate, Ride, RideStatus
from apps.tenancy.models import Role, Tenant, TenantMembership
from apps.tenancy.policy import current_policy
from apps.trust.models import Rating
from apps.trust.services import refresh_trust

PAST_STARS = ([5, 5, 4, 5, 4, 5], [5, 5, 5, 5, 4, 5, 5, 5], [])
RIDER_NAMES = ("أحمد باعلوي", "سعيد بن طالب", "محمد الكثيري")
REQUESTS = (
    {"dx": 0.002, "dy": 0.001, "from": "قرب جامع المحضار، الشرج", "to": "سوق المكلا المركزي", "price": "middle"},
    {"dx": -0.003, "dy": 0.002, "from": "سوق الشرج", "to": "حي الديس", "price": None},
    {"dx": 0.004, "dy": -0.002, "from": "جامعة حضرموت، فوّه", "to": "كورنيش المكلا", "price": "high"},
)
ACTIVE = (RideStatus.REQUESTED, RideStatus.BIDDING)


class Command(BaseCommand):
    help = "Local only: create open requests and rated riders to review the driver app's screens."

    def add_arguments(self, parser):
        parser.add_argument("--tenant", default="mukalla-pilot")
        parser.add_argument("--driver-phone", default="+967700000001")

    def handle(self, *args, **options):
        if not settings.DEBUG or getattr(settings, "RIDEFLOW_ENV", "") != "local":
            raise CommandError("seed_ui_demo only runs on a local development backend.")
        with system_context():
            tenant = Tenant.objects.filter(slug=options["tenant"]).first()
        if tenant is None:
            raise CommandError(f"Unknown tenant: {options['tenant']}")
        with tenant_context(tenant):
            self._seed(options["driver_phone"])

    def _seed(self, phone):
        policy = current_policy()
        driver = DriverProfile.objects.select_related("user").filter(user__phone=phone).first()
        if driver is None:
            raise CommandError(f"{phone} is not a driver of this operator.")
        state = driver_services.eligibility(driver, policy)
        if not (driver.is_online and state["eligible"] and state["presence"]["fresh"]):
            raise CommandError("Go online in the app first, with a fresh location in the city, then run this again.")
        riders = [m.user for m in TenantMembership.objects.filter(role=Role.RIDER).select_related("user").order_by("created_at")[:3]]
        if len(riders) < 3:
            raise CommandError("This operator needs at least 3 riders.")
        city = City.objects.filter(is_active=True).first()
        past_driver = DriverProfile.objects.exclude(pk=driver.pk).select_related("user").first() or driver

        for rider, name, stars in zip(riders, RIDER_NAMES, PAST_STARS, strict=True):
            if not rider.full_name.strip():
                rider.full_name = name
                rider.save(update_fields=["full_name"])
            self._close_open_requests(rider)
            self._past_ratings(rider, past_driver, city, stars, policy)

        for rider, spec in zip(riders, REQUESTS, strict=True):
            ride = self._request(rider, city, spec, policy)
            sent = DispatchCandidate.objects.filter(ride=ride, driver=driver).exists()
            price = "no price" if ride.rider_price_minor is None else f"price {ride.rider_price_minor}"
            self.stdout.write(f"  {spec['from']}: {price}, sent to driver: {'yes' if sent else 'NO'}")
        minutes = policy["rides.bidding_timeout_seconds"] // 60
        self.stdout.write(self.style.SUCCESS(f"3 requests ready; they expire after about {minutes} minutes."))

    def _close_open_requests(self, rider):
        for ride in Ride.objects.filter(rider=rider, status__in=ACTIVE):
            try:
                ride_services.cancel_ride(ride.pk, rider, sm.RIDER, ride.version, reason="ui demo refresh")
            except APIException as exc:
                raise CommandError(f"Could not close request {ride.pk}: {exc.detail}") from exc

    def _past_ratings(self, rider, past_driver, city, stars, policy):
        """Finished rides are created directly: only their ratings matter here, dated in the past to keep reports clean."""
        missing = stars[Rating.objects.filter(ratee=rider, ratee_role="rider").count() :]
        when = timezone.now() - timedelta(days=45)
        center = city.center
        estimate = fare_estimate(center, center, policy)
        for star in missing:
            ride = Ride.objects.create(
                rider=rider,
                city=city,
                pickup=center,
                pickup_landmark="رحلة تجريبية سابقة",
                dropoff=center,
                dropoff_landmark="رحلة تجريبية سابقة",
                status=RideStatus.COMPLETED,
                currency=city.tenant.currency,
                estimate_min_minor=estimate["min_minor"],
                estimate_max_minor=estimate["max_minor"],
                estimated_distance_m=estimate["distance_m"],
                driver=past_driver,
                agreed_fare_minor=max(estimate["min_minor"], 100),
                completed_at=when,
            )
            Ride.objects.filter(pk=ride.pk).update(created_at=when)
            Rating.objects.create(ride=ride, rater=past_driver.user, ratee=rider, rater_role="driver", ratee_role="rider", stars=star)
        if missing:
            refresh_trust(rider, "rider")

    def _request(self, rider, city, spec, policy):
        center = city.center
        pickup = Point(center.x + spec["dx"], center.y + spec["dy"], srid=4326)
        dropoff = Point(pickup.x + 0.012, pickup.y + 0.012, srid=4326)
        estimate = fare_estimate(pickup, dropoff, policy)
        unit = policy["fare.round_unit_minor"]
        price = None
        if spec["price"] == "middle":
            price = (estimate["min_minor"] + estimate["max_minor"]) // 2 // unit * unit
        elif spec["price"] == "high":
            price = estimate["max_minor"]
        return ride_services.create_ride(
            rider,
            pickup=pickup,
            pickup_landmark=spec["from"],
            dropoff=dropoff,
            dropoff_landmark=spec["to"],
            rider_price_minor=price,
        )
