import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.core.context import tenant_context
from apps.drivers.models import DriverProfile
from apps.drivers.services import PHOTO_MAX_BYTES

pytestmark = pytest.mark.django_db

PNG = b"\x89PNG\r\n\x1a\n" + b"x" * 64


def _upload(api, content=PNG, name="me.png"):
    return api.post("/api/v1/driver/photo", {"file": SimpleUploadedFile(name, content)}, fmt="multipart")


def _stored(f, driver):
    with tenant_context(f.tenant.tenant):
        return DriverProfile.objects.get(pk=driver.pk).photo


def _bytes(response):
    return b"".join(response.streaming_content)


def test_photo_shows_at_once_to_the_rider_who_has_an_offer_from_that_driver(ride_flow):
    f = ride_flow
    assert _upload(f.d1_api).status_code == 200
    profile = f.d1_api.get("/api/v1/driver/profile").data
    assert profile["photo_url"].startswith(f"drivers/{f.driver1.pk}/photo")

    ride = f.assigned()
    brief = f.snapshot(ride["id"])["driver"]
    assert brief["photo_url"] == profile["photo_url"]
    r = f.rider_api.get(f"/api/v1/{brief['photo_url']}")
    assert r.status_code == 200
    assert r["Content-Type"] == "image/png"
    assert _bytes(r) == PNG


def test_it_is_on_the_offer_before_the_rider_selects_anyone(ride_flow):
    f = ride_flow
    _upload(f.d1_api)
    ride = f.create()
    url = f"/api/v1/drivers/{f.driver1.pk}/photo"
    assert f.rider_api.get(url).status_code == 404, "no offer yet"
    f.bid(ride["id"])
    offers = f.rider_api.get(f"/api/v1/rides/{ride['id']}/bids").data
    offer = (offers["results"] if isinstance(offers, dict) else offers)[0]
    assert offer["driver"]["photo_url"].startswith(f"drivers/{f.driver1.pk}/photo")
    assert f.rider_api.get(url).status_code == 200


def test_only_the_driver_and_their_riders_can_open_it(ride_flow, h):
    f = ride_flow
    _upload(f.d1_api)
    url = f"/api/v1/drivers/{f.driver1.pk}/photo"
    assert f.d1_api.get(url).status_code == 200, "the driver sees their own"
    assert f.d2_api.get(url).status_code == 404, "another driver"
    assert f.rider_api.get(url).status_code == 404, "a rider with no offer from this driver"
    stranger = h.api(f.tenant, h.member(f.tenant, "rider", name="Stranger"))
    f.assigned()
    assert f.rider_api.get(url).status_code == 200
    assert stranger.get(url).status_code == 404


def test_a_driver_without_a_photo_has_none(ride_flow):
    f = ride_flow
    assert f.d1_api.get("/api/v1/driver/profile").data["photo_url"] is None
    ride = f.assigned()
    assert f.snapshot(ride["id"])["driver"]["photo_url"] is None
    assert f.d1_api.get(f"/api/v1/drivers/{f.driver1.pk}/photo").status_code == 404


def test_only_a_small_image_is_accepted(ride_flow):
    f = ride_flow
    assert _upload(f.d1_api, b"%PDF-1.7 document", "me.pdf").status_code == 400
    assert _upload(f.d1_api, b"not an image", "me.png").status_code == 400
    assert _upload(f.d1_api, PNG + b"x" * PHOTO_MAX_BYTES).status_code == 400
    assert f.d1_api.get("/api/v1/driver/profile").data["photo_url"] is None


def test_a_new_photo_replaces_the_old_file(ride_flow):
    f = ride_flow
    _upload(f.d1_api)
    old = _stored(f, f.driver1)
    storage, name = old.storage, old.name
    assert storage.exists(name)
    other = PNG + b"new"
    assert _upload(f.d1_api, other).status_code == 200
    assert not storage.exists(name)
    assert _bytes(f.d1_api.get(f"/api/v1/drivers/{f.driver1.pk}/photo")) == other


def test_the_driver_can_remove_it(ride_flow):
    f = ride_flow
    _upload(f.d1_api)
    stored = _stored(f, f.driver1)
    storage, name = stored.storage, stored.name
    assert f.d1_api.client.delete("/api/v1/driver/photo").status_code == 204
    assert not storage.exists(name)
    assert f.d1_api.get("/api/v1/driver/profile").data["photo_url"] is None
    assert f.d1_api.client.delete("/api/v1/driver/photo").status_code == 204, "removing nothing is fine"


def test_the_operator_can_see_and_remove_it_but_not_a_rider(ride_flow, h):
    f = ride_flow
    _upload(f.d1_api)
    owner = h.api(f.tenant, h.member(f.tenant, "owner", name="Owner"))
    base = f"/api/v1/admin/drivers/{f.driver1.pk}"
    assert owner.get(base).data["photo_url"] is not None
    assert owner.get(f"{base}/photo").status_code == 200
    assert f.rider_api.post(f"{base}/remove-photo").status_code == 403
    assert owner.post(f"{base}/remove-photo").status_code == 200
    assert owner.get(base).data["photo_url"] is None
    assert owner.get(f"{base}/photo").status_code == 404
