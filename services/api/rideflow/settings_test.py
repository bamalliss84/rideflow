"""Test settings: same PostGIS database engine (RLS and PostGIS are part of what we test), in-memory cache/channels."""

from .settings import *  # noqa: F401,F403
from .settings import REST_FRAMEWORK, SIMPLE_JWT

DEBUG = False
SECRET_KEY = "test-only-secret-key-0123456789abcdefghijkl"
SIMPLE_JWT = {**SIMPLE_JWT, "SIGNING_KEY": SECRET_KEY}
ALLOWED_HOSTS = ["*"]
RIDEFLOW_ENV = "test"
DEV_ADMIN_MFA_BYPASS = False  # tests opt in explicitly
OTP_PROVIDER = "dev"
OTP_DEV_CODE = "123456"
MEDIA_ROOT = "/tmp/rideflow-test-media"

CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}

REST_FRAMEWORK = {
    **REST_FRAMEWORK,
    "DEFAULT_THROTTLE_RATES": {
        **REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"],
        "user": "10000/min",
        "anon": "10000/min",
        "otp_request": "1000/hour",
        "otp_verify": "1000/hour",
        "otp_request_ip": "1000/hour",
        "otp_verify_ip": "1000/hour",
        "platform_login": "1000/hour",
        "location": "10000/min",
        "mfa_ip": "10000/hour",
    },
}

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
