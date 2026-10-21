import uuid

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.core.validators import RegexValidator
from django.db import models
from django.utils import timezone

from apps.core.models import TenantScopedModel

phone_validator = RegexValidator(r"^\+[1-9]\d{7,14}$", "Phone must be in E.164 format, e.g. +967700000000.")


def normalize_phone(phone):
    return "".join(ch for ch in str(phone or "").strip() if ch.isdigit() or ch == "+")


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, phone, password=None, **extra):
        phone = normalize_phone(phone)
        phone_validator(phone)
        user = self.model(phone=phone, **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        return self.create_user(phone, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    """Global identity (owner decision). Tenant access comes only from TenantMembership rows."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=20, unique=True, validators=[phone_validator])
    full_name = models.CharField(max_length=120, blank=True)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False, help_text="Django admin (internal technical administration).")
    is_platform_admin = models.BooleanField(default=False, help_text="RideFlow staff: tenant provisioning only.")
    date_joined = models.DateTimeField(default=timezone.now)

    objects = UserManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = []

    def __str__(self):
        return self.phone


class PhoneOTP(TenantScopedModel):
    """One-time code issued within a tenant's application context. Only an HMAC of the code is stored."""

    phone = models.CharField(max_length=20)
    app = models.ForeignKey("tenancy.TenantApplication", on_delete=models.PROTECT, related_name="+")
    code_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    consumed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["tenant", "phone", "created_at"])]
