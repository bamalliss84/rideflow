import pytest
from django.core.management import call_command
from django.test import Client

from apps.core.context import tenant_context
from apps.core.models import AuditEvent
from apps.rides.models import Ride
from apps.tenancy.models import Tenant

pytestmark = pytest.mark.django_db


def test_liveness_and_readiness():
    client = Client()
    assert client.get("/health/live").json() == {"status": "ok"}
    ready = client.get("/health/ready")
    assert ready.status_code == 200, ready.json()
    assert ready.json()["checks"]["database"]["postgis"]


def test_openapi_schema_generates_without_errors(tmp_path):
    out = tmp_path / "schema.yaml"
    call_command("spectacular", "--validate", "--fail-on-warn", "--file", str(out))
    text = out.read_text()
    for path in (
        "/api/v1/rides/{id}/select",
        "/api/v1/admin/deposit-claims/{id}/approve",
        "/api/v1/platform/tenants",
        "/api/v1/notifications",
    ):
        assert path in text
    assert "Idempotency-Key" in text


def test_swagger_ui_served():
    assert Client().get("/api/docs/").status_code == 200


def test_request_id_header_round_trip():
    r = Client().get("/health/live", HTTP_X_REQUEST_ID="abc-123")
    assert r["X-Request-ID"] == "abc-123"
    r = Client().get("/health/live", HTTP_X_REQUEST_ID="bad id with spaces")
    assert r["X-Request-ID"] != "bad id with spaces"


def test_seed_demo_is_idempotent():
    call_command("seed_demo")
    call_command("seed_demo")
    assert Tenant.objects.filter(slug__in=["mukalla-pilot", "demo-b"]).count() == 2
    tenant = Tenant.objects.get(slug="mukalla-pilot")
    with tenant_context(tenant):
        assert tenant.currency == "YER"
        assert Ride.objects.count() == 0


def test_audit_events_are_append_only():
    event = AuditEvent.objects.create(action="test")
    with pytest.raises(RuntimeError):
        event.save()
    with pytest.raises(RuntimeError):
        event.delete()
