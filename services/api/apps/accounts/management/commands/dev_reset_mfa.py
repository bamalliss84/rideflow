"""Development-only removal of an administrator's TOTP authenticator (lost demo device).

Usage (local Docker only):
    python manage.py dev_reset_mfa +967700000001 --i-understand

Safety:
- Refuses to run unless DJANGO_DEBUG=1 (never in production; production resets go through the audited
  Members / Platform screens or by RideFlow staff).
- Requires the explicit --i-understand flag.
- Never reveals or regenerates a secret: it only deletes the device. MFA is NOT bypassed: the next sign-in
  still requires the first factor and then forces a fresh enrolment confirmed by a valid TOTP code.
- Writes an immutable audit event.
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from apps.accounts.models import MFADevice, User, normalize_phone
from apps.core import audit


class Command(BaseCommand):
    help = "DEVELOPMENT ONLY: remove a user's TOTP authenticator so they re-enrol at next sign-in."

    def add_arguments(self, parser):
        parser.add_argument("phone", help="E.164 phone of the administrator, e.g. +967700000001")
        parser.add_argument("--i-understand", action="store_true", help="Confirm this is an authorized development reset.")

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError("Refused: dev_reset_mfa only runs with DJANGO_DEBUG=1 (development).")
        if not options["i_understand"]:
            raise CommandError("Refused: re-run with --i-understand to confirm this authorized development reset.")
        user = User.objects.filter(phone=normalize_phone(options["phone"])).first()
        if user is None:
            raise CommandError("No user with that phone.")
        deleted, _ = MFADevice.objects.filter(user=user).delete()
        audit.record(
            "dev.mfa_reset",
            actor=None,
            target=user,
            tenant_id=None,
            data={"had_device": bool(deleted), "source": "management_command"},
        )
        if deleted:
            self.stdout.write(self.style.SUCCESS(f"Authenticator removed for {user.phone}. Next sign-in will show the setup QR code."))
        else:
            self.stdout.write(f"{user.phone} had no authenticator; next sign-in already shows the setup QR code.")
