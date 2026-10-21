"""RideFlow API settings. All environment-specific values come from environment variables."""

import os
from datetime import timedelta
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def env(name, default=None):
    return os.environ.get(name, default)


def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name, default=""):
    return [item.strip() for item in env(name, default).split(",") if item.strip()]


DEBUG = env_bool("DJANGO_DEBUG", False)
SECRET_KEY = env("DJANGO_SECRET_KEY")
if not SECRET_KEY:
    if DEBUG:
        SECRET_KEY = "dev-only-insecure-secret-key-change-me-0123456789"
    else:
        raise RuntimeError("DJANGO_SECRET_KEY must be set when DEBUG is off")

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS", "")

INSTALLED_APPS = [
    "daphne",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.gis",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "drf_spectacular",
    "django_filters",
    "channels",
    "apps.core",
    "apps.tenancy",
    "apps.accounts",
    "apps.geo",
    "apps.drivers",
    "apps.subscriptions",
    "apps.rides",
    "apps.trust",
    "apps.notifications",
    "apps.backoffice",
]

MIDDLEWARE = [
    "apps.core.middleware.RequestIdMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "apps.core.middleware.TenantContextMiddleware",
]

ROOT_URLCONF = "rideflow.urls"
WSGI_APPLICATION = "rideflow.wsgi.application"
ASGI_APPLICATION = "rideflow.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {
    "default": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "HOST": env("DB_HOST", "localhost"),
        "PORT": env("DB_PORT", "5432"),
        "NAME": env("DB_NAME", "rideflow"),
        "USER": env("DB_USER", "rideflow_app"),
        "PASSWORD": env("DB_PASSWORD", ""),
        "CONN_MAX_AGE": 0,
        "TEST": {"NAME": "test_rideflow"},
    }
}

AUTH_USER_MODEL = "accounts.User"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 10}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
]

LANGUAGE_CODE = "ar"
LANGUAGES = [("ar", "Arabic"), ("en", "English")]
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_ROOT = env("MEDIA_ROOT", "/data/media")
# Uploaded documents and receipts are private: no MEDIA_URL is routed; files are streamed by authorised endpoints.

REDIS_URL = env("REDIS_URL", "redis://localhost:6379/0")

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
        "KEY_PREFIX": "rideflow",
    }
}

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL], "prefix": "rideflow:ws"},
    }
}

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["apps.accounts.authentication.TenantJWTAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_PAGINATION_CLASS": "apps.core.pagination.StandardPagination",
    "PAGE_SIZE": 25,
    "DEFAULT_FILTER_BACKENDS": [
        "apps.core.filters.TenantFilterBackend",
        "rest_framework.filters.OrderingFilter",
    ],
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_THROTTLE_CLASSES": [
        "apps.core.throttling.TenantUserRateThrottle",
        "apps.core.throttling.TenantAnonRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "user": env("THROTTLE_USER", "600/min"),
        "anon": env("THROTTLE_ANON", "60/min"),
        "otp_request": env("THROTTLE_OTP_REQUEST", "5/hour"),  # per phone + app
        "otp_verify": env("THROTTLE_OTP_VERIFY", "20/hour"),  # per phone + app
        "otp_request_ip": env("THROTTLE_OTP_REQUEST_IP", "60/hour"),
        "otp_verify_ip": env("THROTTLE_OTP_VERIFY_IP", "120/hour"),
        "platform_login": env("THROTTLE_PLATFORM_LOGIN", "10/hour"),
        "location": env("THROTTLE_LOCATION", "120/min"),
        "mfa_ip": env("THROTTLE_MFA_IP", "60/hour"),
    },
    "EXCEPTION_HANDLER": "apps.core.exceptions.api_exception_handler",
    "TEST_REQUEST_DEFAULT_FORMAT": "json",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(seconds=int(env("JWT_ACCESS_SECONDS", "900"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(seconds=int(env("JWT_REFRESH_SECONDS", "1209600"))),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": False,
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "uid",
    "SIGNING_KEY": SECRET_KEY,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

SPECTACULAR_SETTINGS = {
    "TITLE": "RideFlow API",
    "DESCRIPTION": (
        "Multi-tenant ride-hailing backend. Tenant is resolved from the authenticated token (claim `tid`), "
        "never from client payloads. Mutations on critical resources require an `Idempotency-Key` header; "
        "ride lifecycle actions also require `expected_version`. WebSocket hints: `/ws/v1/events/?token=<access>`."
    ),
    "VERSION": "1.0.0-phase1",
    "SERVE_INCLUDE_SCHEMA": False,
    "COMPONENT_SPLIT_REQUEST": True,
    "SCHEMA_PATH_PREFIX": r"/api/v1",
    "ENUM_NAME_OVERRIDES": {
        "RideStatusEnum": "apps.rides.models.RideStatus",
        "MembershipRoleEnum": "apps.tenancy.models.Role",
        "DriverStatusEnum": "apps.drivers.models.DriverStatus",
        "ReviewStatusEnum": "apps.drivers.models.ReviewStatus",
        "TenantStatusEnum": "apps.tenancy.models.TenantStatus",
        "DepositClaimStatusEnum": "apps.subscriptions.models.ClaimStatus",
        "ViolationStatusEnum": "apps.trust.models.ViolationStatus",
        "DisputeStatusEnum": "apps.trust.models.DisputeStatus",
        "AppealStatusEnum": "apps.trust.models.AppealStatus",
        "EnforcementStatusEnum": "apps.trust.models.EnforcementStatus",
        "BidStatusEnum": "apps.rides.models.BidStatus",
        "AmendmentStatusEnum": "apps.rides.models.AmendmentStatus",
        "ViolationKindEnum": "apps.trust.models.ViolationKind",
        "EvidenceKindEnum": "apps.rides.models.EvidenceKind",
    },
}

# OTP
OTP_PROVIDER = env("OTP_PROVIDER", "dev")
if OTP_PROVIDER == "dev" and not DEBUG:
    # The development adapter logs codes; it must never run outside development.
    raise RuntimeError("OTP_PROVIDER=dev is only allowed with DJANGO_DEBUG=1")
OTP_DEV_CODE = env("OTP_DEV_CODE", "")
OTP_TTL_SECONDS = int(env("OTP_TTL_SECONDS", "300"))
OTP_MAX_ATTEMPTS = int(env("OTP_MAX_ATTEMPTS", "5"))

# Upload limits (tenant policy may lower these)
UPLOAD_MAX_BYTES = int(env("UPLOAD_MAX_BYTES", str(5 * 1024 * 1024)))
DATA_UPLOAD_MAX_MEMORY_SIZE = UPLOAD_MAX_BYTES + 1024 * 1024

# Administrator MFA (TOTP). Required for staff roles and the platform scope.
ADMIN_MFA_REQUIRED = env_bool("ADMIN_MFA_REQUIRED", True)
MFA_ENCRYPTION_KEY = env("MFA_ENCRYPTION_KEY", "")  # Fernet key; derived from SECRET_KEY when empty (dev)

IDEMPOTENCY_TTL_HOURS = int(env("IDEMPOTENCY_TTL_HOURS", "48"))

SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
if not DEBUG:
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"context": {"()": "apps.core.logging.ContextFilter"}},
    "formatters": {
        "structured": {"format": "%(asctime)s %(levelname)s %(name)s request_id=%(request_id)s tenant_id=%(tenant_id)s %(message)s"}
    },
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "structured", "filters": ["context"]}},
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", "INFO")},
    "loggers": {"django.db.backends": {"level": "WARNING"}},
}
