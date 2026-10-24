"""Dedicated, idempotent tenant for the Playwright end-to-end suite (local development only).

It never touches the owner's demo tenants. Workflow records (drivers, rides, claims...) are created by the
suite itself through the public API with fresh phone numbers, so repeated runs do not collide.
"""

import json

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.context import tenant_context
from apps.subscriptions.models import DepositAccount, SubscriptionPlan
from apps.tenancy.models import AppType, Role, Tenant

from .seed_demo import Command as DemoSeed

E2E = {
    "tenant": {
        "name": "E2E QA Operator (test data)",
        "slug": "e2e-qa",
        "currency": "YER",
        "currency_minor_units": 2,
        "time_zone": "Asia/Aden",
        "locale": "ar",
    },
    "apps": {AppType.RIDER: "e2e-qa-rider", AppType.DRIVER: "e2e-qa-driver", AppType.ADMIN: "e2e-qa-admin"},
    "city": {"name": "E2E City", "slug": "e2e-city", "center": (49.3500, 14.7000), "bbox": (49.30, 14.65, 49.40, 14.75)},
    "staff": [
        ("+967799000001", "E2E Owner", Role.OWNER),
        ("+967799000002", "E2E Reviewer", Role.REVIEWER),
        ("+967799000003", "E2E Finance", Role.FINANCE),
        ("+967799000004", "E2E Reviewer Two", Role.REVIEWER),
        ("+967799000005", "E2E Support", Role.SUPPORT),
        ("+967799000006", "E2E Login Owner", Role.OWNER),
        # Rotated by the UI-login test: OTP requests are limited to 5 per hour per phone.
        *[(f"+96779900010{i}", f"E2E Login Owner {i}", Role.OWNER) for i in range(6)],
    ],
    "riders": [],
    "drivers": [],
    "monthly_price_minor": 500000,
}


class Command(BaseCommand):
    help = "Creates the dedicated e2e-qa tenant used by the Playwright suite (DEBUG only)."

    def add_arguments(self, parser):
        parser.add_argument("--json", action="store_true", help="Print ids for the test runner as JSON.")

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError("seed_e2e is only available with DJANGO_DEBUG=1.")
        with transaction.atomic():
            DemoSeed()._tenant(E2E)
        tenant = Tenant.objects.get(slug=E2E["tenant"]["slug"])
        with tenant_context(tenant):
            data = {
                "tenant_id": str(tenant.pk),
                "apps": {str(k): v for k, v in E2E["apps"].items()},
                "center": {"lng": E2E["city"]["center"][0], "lat": E2E["city"]["center"][1]},
                "monthly_plan_id": str(SubscriptionPlan.objects.get(code="monthly").pk),
                "monthly_price_minor": E2E["monthly_price_minor"],
                "deposit_account_id": str(DepositAccount.objects.order_by("created_at").first().pk),
                "staff": {name.split(" ", 1)[1].lower().replace(" ", "_"): phone for phone, name, _role in E2E["staff"][:6]},
                "login_phones": [phone for phone, _name, _role in E2E["staff"][6:]],
            }
        if options["json"]:
            self.stdout.write(json.dumps(data))
        else:
            self.stdout.write(self.style.SUCCESS(f"e2e tenant ready: {data['tenant_id']}"))
