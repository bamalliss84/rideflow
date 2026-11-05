import pytest

pytestmark = pytest.mark.django_db


def test_riders_and_drivers_read_the_operators_waiting_times(ride_flow):
    f = ride_flow
    for api in (f.rider_api, f.d1_api):
        r = api.get("/api/v1/wait-times")
        assert r.status_code == 200
        assert r.data["bidding_timeout_seconds"] == 900
        assert r.data["bid_expiry_seconds"] == 120
        assert r.data["driver_confirm_timeout_seconds"] == 60
        assert r.data["free_cancel_after_match_seconds"] == 120
        assert r.data["noshow_wait_seconds"] == 300
        assert r.data["location_stale_seconds"] == 120
        assert r.data["rating_window_days"] == 7
