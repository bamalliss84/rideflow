import pytest

from apps.core import context

from .factories import Api, add_roles, api_for, make_driver, make_member, make_tenant, ride_payload


@pytest.fixture(autouse=True)
def _reset_context():
    context.set_system()
    yield
    context.set_system()


@pytest.fixture
def ta(db):
    return make_tenant("alpha")


@pytest.fixture
def tb(db):
    return make_tenant("beta", currency="SAR", time_zone="Asia/Riyadh", center=(48.79, 15.94))


@pytest.fixture
def h():
    """Helper namespace so tests read naturally: h.driver(ta), h.api(ta, user) ..."""

    class H:
        member = staticmethod(make_member)
        driver = staticmethod(make_driver)
        api = staticmethod(api_for)
        roles = staticmethod(add_roles)
        ride_payload = staticmethod(ride_payload)
        Api = Api

    return H


@pytest.fixture
def ride_flow(ta, h):
    """A rider, two eligible online drivers and helpers to drive a ride to any state."""

    rider = h.member(ta, "rider", name="Rider One")
    d1 = h.driver(ta, offset=(0.001, 0.001))
    d2 = h.driver(ta, offset=(0.002, 0.002))

    class Flow:
        tenant = ta
        rider_user = rider
        rider_api = h.api(ta, rider)
        driver1 = d1
        driver2 = d2
        d1_api = h.api(ta, d1.user)
        d2_api = h.api(ta, d2.user)

        def create(self):
            response = self.rider_api.post("/api/v1/rides", h.ride_payload(ta))
            assert response.status_code == 201, response.data
            return response.data

        def bid(self, ride_id, api=None, amount=150000, eta=300):
            response = (api or self.d1_api).post(f"/api/v1/rides/{ride_id}/bids", {"amount_minor": amount, "eta_seconds": eta})
            assert response.status_code == 201, response.data
            return response.data

        def snapshot(self, ride_id, api=None):
            return (api or self.rider_api).get(f"/api/v1/rides/{ride_id}").data

        def assigned(self):
            ride = self.create()
            bid = self.bid(ride["id"])
            r = self.rider_api.post(f"/api/v1/rides/{ride['id']}/select", {"bid_id": bid["id"], "expected_version": ride["version"]})
            assert r.status_code == 200, r.data
            r = self.d1_api.post(f"/api/v1/rides/{ride['id']}/confirm", {"expected_version": r.data["version"]})
            assert r.status_code == 200, r.data
            return r.data

        def arrived(self, accuracy=10.0, dx=0.0):
            ride = self.assigned()
            lng, lat = ta.center
            r = self.d1_api.post(
                f"/api/v1/rides/{ride['id']}/arrive",
                {"expected_version": ride["version"], "lat": lat, "lng": lng + dx, "accuracy_m": accuracy},
            )
            assert r.status_code == 200, r.data
            return r.data

        def completed(self):
            ride = self.arrived()
            r = self.d1_api.post(f"/api/v1/rides/{ride['id']}/start", {"expected_version": ride["version"]})
            assert r.status_code == 200, r.data
            r = self.d1_api.post(f"/api/v1/rides/{ride['id']}/complete", {"expected_version": r.data["version"]})
            assert r.status_code == 200, r.data
            return r.data

    return Flow()
