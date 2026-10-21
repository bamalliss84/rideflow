import time

from django.core.management.base import BaseCommand
from django.db import close_old_connections


class Command(BaseCommand):
    help = "Applies ride timers (bid expiry, driver-confirmation timeout, unmatched expiry) for every tenant."

    def add_arguments(self, parser):
        parser.add_argument("--loop", type=int, default=0, help="Repeat every N seconds (0 = run once).")

    def handle(self, *args, **options):
        from apps.rides.services import process_all_timeouts

        interval = options["loop"]
        while True:
            close_old_connections()
            processed = process_all_timeouts()
            if processed or not interval:
                self.stdout.write(f"timeouts processed: {processed}")
            if not interval:
                return
            time.sleep(interval)
