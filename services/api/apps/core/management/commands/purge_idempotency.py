from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.core.models import IdempotencyRecord


class Command(BaseCommand):
    help = "Deletes idempotency records older than IDEMPOTENCY_TTL_HOURS."

    def handle(self, *args, **options):
        cutoff = timezone.now() - timedelta(hours=settings.IDEMPOTENCY_TTL_HOURS)
        deleted, _ = IdempotencyRecord.objects.filter(created_at__lt=cutoff).delete()
        self.stdout.write(f"deleted {deleted} idempotency records")
