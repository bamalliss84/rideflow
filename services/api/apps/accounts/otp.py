"""OTP delivery adapters. Only a development fake exists in Phase 1 (no SMS provider approved)."""

import hashlib
import hmac
import logging
import secrets

from django.conf import settings

logger = logging.getLogger("rideflow.otp")


class OTPProviderUnavailable(RuntimeError):
    pass


def generate_code():
    if settings.OTP_PROVIDER == "dev" and settings.OTP_DEV_CODE:
        return settings.OTP_DEV_CODE
    return f"{secrets.randbelow(10**6):06d}"


def hash_code(phone, code):
    return hmac.new(settings.SECRET_KEY.encode(), f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def send_code(phone, code, tenant):
    if settings.OTP_PROVIDER == "dev":
        # Development only: never enabled with a real provider. Mask the phone in logs.
        logger.info("DEV OTP for ***%s (tenant %s): %s", phone[-3:], tenant.slug, code)
        return
    raise OTPProviderUnavailable("No OTP provider is configured for this environment.")
