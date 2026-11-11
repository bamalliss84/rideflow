"""D051: the apps read the operator's region and settings from the server and notice every change."""

from unittest import mock

import pytest
from rest_framework.test import APIClient

from apps.tenancy import app_config

from .factories import Api, api_for, make_member, make_tenant, make_user

pytestmark = pytest.mark.django_db


def _public(client_id):
    return APIClient().get("/api/v1/app/config", HTTP_X_RIDEFLOW_APP=client_id)


def test_the_app_header_chooses_the_operator_and_its_region(ta, tb):
    for t, currency in ((ta, "YER"), (tb, "SAR")):
        r = _public(f"{t.tenant.slug}-driver")
        assert r.status_code == 200
        region = r.data["region"]
        assert region["currency"] == currency
        assert region["currency_symbol"] == currency, "no symbol set: the code is shown"
        assert region["distance_unit"] == "km"
        lng, lat = t.center
        assert region["map_center"] == {"lat": pytest.approx(lat), "lng": pytest.approx(lng)}
        assert r[app_config.HEADER] == r.data["version"]


def test_unknown_app_gets_nothing():
    assert _public("nope-driver").status_code in (400, 401, 403)


def test_the_settings_the_apps_run_on(ta):
    settings = _public("alpha-rider").data["settings"]
    assert settings["app.driver_requests_refresh_seconds"] == 20
    assert settings["app.connection_cut_grace_seconds"] == 15
    assert settings["app.offer_eta_choices_minutes"] == [3, 5, 8, 10, 15]
    assert settings["fare.bid_step_minor"] == 5000
    assert "dispatch.initial_radius_m" not in settings, "only what the apps use"


def test_a_settings_change_reaches_the_apps(ta):
    owner_api = api_for(ta, make_member(ta, "owner"))
    before = _public("alpha-driver").data["version"]
    with mock.patch.object(app_config, "announce") as announce:
        r = owner_api.post("/api/v1/admin/config", {"params": {"app.driver_requests_refresh_seconds": 45}})
        assert r.status_code == 201, r.data
    announce.assert_called_once()
    after = _public("alpha-driver").data
    assert after["version"] != before
    assert after["settings"]["app.driver_requests_refresh_seconds"] == 45


def test_every_tenant_response_carries_the_version(ta):
    rider_api = api_for(ta, make_member(ta, "rider"))
    version = _public("alpha-rider").data["version"]
    r = rider_api.get("/api/v1/wait-times")
    assert r.status_code == 200
    assert r[app_config.HEADER] == version


def test_offer_choices_are_checked(ta):
    owner_api = api_for(ta, make_member(ta, "owner"))
    for bad in ([], [5, 5], [0, 5], list(range(1, 10)), ["5"]):
        r = owner_api.post("/api/v1/admin/config", {"params": {"app.offer_eta_choices_minutes": bad}})
        assert r.status_code == 400, bad


def test_platform_sets_where_an_operator_runs(db):
    admin = make_user("Platform")
    admin.is_platform_admin = True
    admin.save()
    platform_api = Api(admin, platform=True)
    t = make_tenant("gamma", currency="SAR", time_zone="Asia/Riyadh")
    url = f"/api/v1/platform/tenants/{t.tenant.pk}"
    with mock.patch.object(app_config, "announce") as announce:
        r = platform_api.patch(url, {"country": "sa", "currency_symbol": "ر.س", "phone_country_code": "+966", "distance_unit": "km"})
        assert r.status_code == 200, r.data
    announce.assert_called()
    assert r.data["country"] == "SA"
    region = _public("gamma-rider").data["region"]
    assert (region["country"], region["currency_symbol"], region["phone_country_code"]) == ("SA", "ر.س", "+966")
    for bad in ({"country": "SAU"}, {"phone_country_code": "966"}, {"distance_unit": "ft"}):
        assert platform_api.patch(url, bad).status_code == 400, bad
