import pytest
from django.core.management import call_command
from django.core.management.base import CommandError

from apps.core.context import tenant_context
from apps.rides.models import Ride
from apps.trust.models import Rating

from .factories import api_for, make_driver, make_member, make_tenant

pytestmark = pytest.mark.django_db


def _setup(settings, slug):
    settings.DEBUG = True
    settings.RIDEFLOW_ENV = "local"
    t = make_tenant(slug)
    driver = make_driver(t)
    make_driver(t, offset=(0.002, 0.002))
    for _ in range(3):
        make_member(t, "rider")
    return t, driver


def test_creates_requests_and_rated_riders_and_can_run_again(settings):
    t, driver = _setup(settings, "ui-demo")
    call_command("seed_ui_demo", tenant=t.tenant.slug, driver_phone=driver.user.phone)

    api = api_for(t, driver.user)
    offers = api.get("/api/v1/driver/ride-offers").data
    assert len(offers) == 3
    assert sorted(o["rider_price_minor"] is not None for o in offers) == [False, True, True]
    assert sorted(o["rider"]["trust"]["rating_provisional"] for o in offers) == [False, False, True]
    for offer in offers:
        price = offer["rider_price_minor"]
        assert price is None or price >= offer["estimate"]["min_minor"]

    with tenant_context(t.tenant):
        ratings = Rating.objects.count()
        first_ids = set(Ride.objects.filter(status="bidding").values_list("id", flat=True))
    call_command("seed_ui_demo", tenant=t.tenant.slug, driver_phone=driver.user.phone)
    with tenant_context(t.tenant):
        assert Rating.objects.count() == ratings  # past ratings aren't duplicated
        fresh_ids = set(Ride.objects.filter(status="bidding").values_list("id", flat=True))
    assert len(fresh_ids) == 3 and not fresh_ids & first_ids
    assert len(api.get("/api/v1/driver/ride-offers").data) == 3


def test_refuses_outside_local_development(settings):
    t, driver = _setup(settings, "ui-demo-prod")
    settings.RIDEFLOW_ENV = "production"
    with pytest.raises(CommandError, match="local development"):
        call_command("seed_ui_demo", tenant=t.tenant.slug, driver_phone=driver.user.phone)
    settings.RIDEFLOW_ENV = "local"
    settings.DEBUG = False
    with pytest.raises(CommandError, match="local development"):
        call_command("seed_ui_demo", tenant=t.tenant.slug, driver_phone=driver.user.phone)


def test_refuses_while_the_driver_is_offline(settings):
    settings.DEBUG = True
    settings.RIDEFLOW_ENV = "local"
    t = make_tenant("ui-demo-off")
    driver = make_driver(t, online=False)
    with pytest.raises(CommandError, match="Go online"):
        call_command("seed_ui_demo", tenant=t.tenant.slug, driver_phone=driver.user.phone)
