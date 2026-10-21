"""Reproducible demo data (idempotent). Two tenants so isolation can be demonstrated manually.

All phones, accounts and bank details are fake. Policy values are the PROVISIONAL/PROPOSED defaults.
"""

import os
from datetime import timedelta

from django.contrib.gis.geos import MultiPolygon, Point, Polygon
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.core.context import tenant_context
from apps.drivers.models import DocumentType, DriverDocument, DriverProfile, DriverStatus, ReviewStatus, Vehicle
from apps.geo.models import City, DriverLocation, ServiceArea
from apps.subscriptions.models import DepositAccount, SubscriptionPlan
from apps.subscriptions.services import start_trial
from apps.tenancy.models import AppType, Role, Tenant, TenantApplication, TenantConfig, TenantMembership

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64

TENANTS = [
    {
        "tenant": {
            "name": "Mukalla Pilot Operator (demo)",
            "slug": "mukalla-pilot",
            "currency": "YER",
            "currency_minor_units": 2,
            "time_zone": "Asia/Aden",
            "locale": "ar",
        },
        "apps": {AppType.RIDER: "demo-mukalla-rider", AppType.DRIVER: "demo-mukalla-driver", AppType.ADMIN: "demo-mukalla-admin"},
        # Approximate demo geometry around Mukalla; must be replaced with operator-surveyed areas.
        "city": {"name": "المكلا", "slug": "mukalla", "center": (49.1242, 14.5426), "bbox": (49.05, 14.48, 49.25, 14.62)},
        "staff": [
            ("+967700000001", "Demo Owner", Role.OWNER),
            ("+967700000002", "Demo Finance", Role.FINANCE),
            ("+967700000003", "Demo Reviewer", Role.REVIEWER),
        ],
        "riders": ["+967711000001", "+967711000002", "+967711000003"],
        "drivers": ["+967722000001", "+967722000002", "+967722000003", "+967722000004", "+967722000005"],
        "monthly_price_minor": 500000,  # 5,000 YER (D009 PROPOSED)
    },
    {
        "tenant": {
            "name": "Demo Operator B",
            "slug": "demo-b",
            "currency": "SAR",
            "currency_minor_units": 2,
            "time_zone": "Asia/Riyadh",
            "locale": "ar",
        },
        "apps": {AppType.RIDER: "demo-b-rider", AppType.DRIVER: "demo-b-driver", AppType.ADMIN: "demo-b-admin"},
        "city": {"name": "Demo City B", "slug": "demo-city-b", "center": (48.7900, 15.9400), "bbox": (48.70, 15.88, 48.88, 16.00)},
        "staff": [("+967700000101", "Operator B Owner", Role.OWNER)],
        "riders": ["+967711000101"],
        "drivers": ["+967722000101"],
        "monthly_price_minor": 5000,
    },
]


class Command(BaseCommand):
    help = "Loads idempotent demo data for local development (two tenants)."

    def handle(self, *args, **options):
        self._platform_admin()
        for spec in TENANTS:
            with transaction.atomic():
                self._tenant(spec)
        self.stdout.write(self.style.SUCCESS("demo data ready"))
        for spec in TENANTS:
            self.stdout.write(f"  {spec['tenant']['slug']}: apps {list(spec['apps'].values())}")

    def _platform_admin(self):
        phone = os.environ.get("DEMO_PLATFORM_ADMIN_PHONE", "+967700000000")
        password = os.environ.get("DEMO_PLATFORM_ADMIN_PASSWORD")
        user = User.objects.filter(phone=phone).first() or User.objects.create_user(phone, full_name="Platform Admin")
        user.is_platform_admin = True
        user.is_staff = True
        user.is_superuser = True
        if password:
            user.set_password(password)
        user.save()

    def _user(self, phone, name):
        return User.objects.filter(phone=phone).first() or User.objects.create_user(phone, full_name=name)

    def _tenant(self, spec):
        tenant, _ = Tenant.objects.get_or_create(slug=spec["tenant"]["slug"], defaults=spec["tenant"])
        for app_type, client_id in spec["apps"].items():
            TenantApplication.objects.get_or_create(
                client_id=client_id, defaults={"tenant": tenant, "app_type": app_type, "name": client_id}
            )
        with tenant_context(tenant):
            if not TenantConfig.objects.exists():
                TenantConfig.objects.create(
                    version=1,
                    effective_from=timezone.now() - timedelta(minutes=1),
                    params={},
                    note="Demo seed: PROVISIONAL/PROPOSED defaults, not approved policy",
                )
            c = spec["city"]
            minx, miny, maxx, maxy = c["bbox"]
            ring = ((minx, miny), (maxx, miny), (maxx, maxy), (minx, maxy), (minx, miny))
            city, _ = City.objects.get_or_create(
                slug=c["slug"],
                defaults={
                    "name": c["name"],
                    "center": Point(*c["center"], srid=4326),
                    "boundary": MultiPolygon(Polygon(ring, srid=4326), srid=4326),
                },
            )
            if not ServiceArea.objects.filter(city=city).exists():
                ServiceArea.objects.create(city=city, name=f"{c['name']} (demo area)", area=Polygon(ring, srid=4326))
            SubscriptionPlan.objects.get_or_create(
                code="founder-trial",
                defaults={"name": "Founder trial (D009 proposed)", "price_minor": 0, "duration_days": 60, "is_trial": True},
            )
            SubscriptionPlan.objects.get_or_create(
                code="monthly",
                defaults={"name": "Monthly (D009 proposed)", "price_minor": spec["monthly_price_minor"], "duration_days": 30},
            )
            if not DepositAccount.objects.exists():
                DepositAccount.objects.create(
                    bank_name="DEMO BANK (not real)",
                    account_name=tenant.name,
                    account_number="DEMO-0000",
                    instructions="Demo only. Do not deposit.",
                )
            for phone, name, role in spec["staff"]:
                TenantMembership.objects.get_or_create(user=self._user(phone, name), role=role)
            for i, phone in enumerate(spec["riders"], start=1):
                TenantMembership.objects.get_or_create(user=self._user(phone, f"راكب {i}"), role=Role.RIDER)
            for i, phone in enumerate(spec["drivers"], start=1):
                self._driver(tenant, city, phone, i)

    def _driver(self, tenant, city, phone, index):
        user = self._user(phone, f"سائق {index}")
        TenantMembership.objects.get_or_create(user=user, role=Role.DRIVER)
        driver, created = DriverProfile.objects.get_or_create(user=user)
        if not created and driver.status == DriverStatus.APPROVED:
            return
        vehicle, _ = Vehicle.objects.get_or_create(
            plate_number=f"{tenant.slug[:3].upper()}-{1000 + index}",
            defaults={
                "driver": driver,
                "make": "Toyota",
                "model": "Corolla",
                "color": "White",
                "year": 2015,
                "status": ReviewStatus.APPROVED,
            },
        )
        for doc_type in (DocumentType.NATIONAL_ID, DocumentType.DRIVING_LICENSE, DocumentType.VEHICLE_REGISTRATION):
            if not DriverDocument.objects.filter(driver=driver, doc_type=doc_type).exists():
                doc = DriverDocument(
                    driver=driver,
                    doc_type=doc_type,
                    number=f"DEMO-{index}-{doc_type[:3]}",
                    expires_at=timezone.localdate() + timedelta(days=365),
                    content_type="image/png",
                    sha256=f"demo{index}{doc_type}".ljust(64, "0")[:64],
                    status=ReviewStatus.APPROVED,
                    vehicle=vehicle if doc_type == DocumentType.VEHICLE_REGISTRATION else None,
                )
                doc.file.save(f"{doc_type}.png", ContentFile(PNG), save=False)
                doc.save()
        driver.status = DriverStatus.APPROVED
        driver.reviewed_at = timezone.now()
        driver.is_online = True
        driver.online_since = timezone.now()
        driver.save()
        start_trial(driver)
        lng, lat = city.center.x + 0.002 * index, city.center.y + 0.0015 * index
        DriverLocation.objects.update_or_create(
            driver=driver,
            defaults={"point": Point(lng, lat, srid=4326), "accuracy_m": 10, "device_ts": timezone.now(), "server_ts": timezone.now()},
        )
