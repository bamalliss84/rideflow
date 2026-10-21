"""Test factories. Every tenant-scoped object is created inside an explicit tenant context."""

import itertools
import uuid
from datetime import timedelta
from types import SimpleNamespace

from django.contrib.gis.geos import Point, Polygon
from django.core.files.base import ContentFile
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.authentication import issue_tokens
from apps.accounts.models import User
from apps.core.context import tenant_context
from apps.drivers.models import DocumentType, DriverDocument, DriverProfile, DriverStatus, ReviewStatus, Vehicle
from apps.geo.models import City, DriverLocation, ServiceArea
from apps.subscriptions.models import DepositAccount, DriverSubscription, SubscriptionPlan, SubscriptionSource
from apps.tenancy.models import AppType, Tenant, TenantApplication, TenantMembership

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
PDF = b"%PDF-1.4\n%test\n"
_phones = itertools.count(1)
_plates = itertools.count(1)


def phone():
    return f"+9677{next(_phones):08d}"


def make_tenant(slug, currency="YER", time_zone="Asia/Aden", center=(49.1242, 14.5426)):
    tenant = Tenant.objects.create(name=f"Tenant {slug}", slug=slug, currency=currency, time_zone=time_zone)
    apps = {
        app_type: TenantApplication.objects.create(tenant=tenant, app_type=app_type, name=app_type, client_id=f"{slug}-{app_type}")
        for app_type in AppType.values
    }
    lng, lat = center
    ring = ((lng - 0.1, lat - 0.1), (lng + 0.1, lat - 0.1), (lng + 0.1, lat + 0.1), (lng - 0.1, lat + 0.1), (lng - 0.1, lat - 0.1))
    with tenant_context(tenant):
        city = City.objects.create(name=f"City {slug}", slug=f"city-{slug}", center=Point(lng, lat, srid=4326))
        ServiceArea.objects.create(city=city, name="Area", area=Polygon(ring, srid=4326))
        trial = SubscriptionPlan.objects.create(code="trial", name="Trial", price_minor=0, duration_days=60, is_trial=True)
        monthly = SubscriptionPlan.objects.create(code="monthly", name="Monthly", price_minor=500000, duration_days=30)
        account = DepositAccount.objects.create(bank_name="Test Bank", account_name=slug, account_number="0001")
    return SimpleNamespace(tenant=tenant, apps=apps, city=city, trial=trial, monthly=monthly, account=account, center=center)


def make_user(name="Test User"):
    return User.objects.create_user(phone(), full_name=name)


def add_roles(t, user, *roles):
    with tenant_context(t.tenant):
        for role in roles:
            TenantMembership.objects.get_or_create(user=user, role=role)
    return user


def make_member(t, *roles, name="Member"):
    return add_roles(t, make_user(name), *roles)


def make_driver(t, *, approved=True, online=True, subscribed=True, offset=(0.001, 0.001), user=None, located=True):
    user = user or make_user("Driver Person")
    add_roles(t, user, "driver")
    with tenant_context(t.tenant):
        driver = DriverProfile.objects.create(user=user)
        vehicle = Vehicle.objects.create(
            driver=driver,
            plate_number=f"T-{next(_plates)}",
            make="Toyota",
            model="Corolla",
            color="White",
            status=ReviewStatus.APPROVED if approved else ReviewStatus.PENDING,
        )
        for doc_type in (DocumentType.NATIONAL_ID, DocumentType.DRIVING_LICENSE, DocumentType.VEHICLE_REGISTRATION):
            doc = DriverDocument(
                driver=driver,
                doc_type=doc_type,
                content_type="image/png",
                sha256=uuid.uuid4().hex + uuid.uuid4().hex[:32],
                expires_at=timezone.localdate() + timedelta(days=365),
                status=ReviewStatus.APPROVED if approved else ReviewStatus.PENDING,
                vehicle=vehicle if doc_type == DocumentType.VEHICLE_REGISTRATION else None,
            )
            doc.file.save("doc.png", ContentFile(PNG), save=False)
            doc.save()
        if approved:
            driver.status = DriverStatus.APPROVED
        if subscribed:
            now = timezone.now()
            DriverSubscription.objects.create(
                driver=driver, starts_at=now - timedelta(days=1), ends_at=now + timedelta(days=29), source=SubscriptionSource.MANUAL
            )
        driver.is_online = online and approved
        driver.save()
        if located:
            lng, lat = t.center
            DriverLocation.objects.create(
                driver=driver,
                point=Point(lng + offset[0], lat + offset[1], srid=4326),
                accuracy_m=10,
                device_ts=timezone.now(),
                server_ts=timezone.now(),
            )
    return driver


class Api:
    """APIClient bound to a user + tenant token; POST/PATCH add a fresh Idempotency-Key unless one is given."""

    def __init__(self, user, tenant=None, platform=False, app=None):
        self.user = user
        self.client = APIClient()
        tokens = issue_tokens(user, scope="platform" if platform else "tenant", tenant=tenant, app=app)
        self.tokens = tokens
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    def get(self, url, data=None, **extra):
        return self.client.get(url, data, **extra)

    def post(self, url, data=None, key=None, fmt="json", **extra):
        extra.setdefault("HTTP_IDEMPOTENCY_KEY", key or str(uuid.uuid4()))
        return self.client.post(url, data or {}, format=fmt, **extra)

    def patch(self, url, data=None, **extra):
        return self.client.patch(url, data or {}, format="json", **extra)


def api_for(t, user):
    return Api(user, tenant=t.tenant)


def ride_payload(t, dx=0.0, dy=0.0):
    lng, lat = t.center
    return {
        "pickup": {"lat": lat + dy, "lng": lng + dx},
        "pickup_landmark": "قرب الجامع",
        "dropoff": {"lat": lat + 0.02, "lng": lng + 0.02},
        "dropoff_landmark": "السوق",
    }
