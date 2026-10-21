"""Driver subscriptions paid to the operating tenant by bank deposit (D003, D017).

Distinct from future SaaS operator billing (tenant -> RideFlow), which will live in a separate module/ledger.
"""

from django.conf import settings
from django.db import models

from apps.core.files import tenant_upload_to
from apps.core.models import AppendOnlyMixin, TenantScopedModel


class SubscriptionPlan(TenantScopedModel):
    code = models.SlugField(max_length=40)
    name = models.CharField(max_length=120)
    price_minor = models.BigIntegerField()
    duration_days = models.PositiveIntegerField()
    is_trial = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "price_minor"]
        constraints = [
            models.UniqueConstraint(fields=["tenant", "code"], name="uniq_plan_code_per_tenant"),
            models.CheckConstraint(condition=models.Q(price_minor__gte=0), name="plan_price_non_negative"),
        ]


class DepositAccount(TenantScopedModel):
    bank_name = models.CharField(max_length=120)
    account_name = models.CharField(max_length=120)
    account_number = models.CharField(max_length=64)
    instructions = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)


class ClaimStatus(models.TextChoices):
    SUBMITTED = "submitted", "Submitted"
    FIRST_APPROVED = "first_approved", "First approval (awaiting checker)"
    APPROVED = "approved", "Approved"
    REJECTED = "rejected", "Rejected"


class DepositClaim(TenantScopedModel):
    driver = models.ForeignKey("drivers.DriverProfile", on_delete=models.PROTECT, related_name="deposit_claims")
    plan = models.ForeignKey(SubscriptionPlan, on_delete=models.PROTECT, related_name="+")
    deposit_account = models.ForeignKey(DepositAccount, on_delete=models.PROTECT, related_name="+")
    amount_minor = models.BigIntegerField()
    expected_amount_minor = models.BigIntegerField()
    discount_pct = models.PositiveSmallIntegerField(default=0)
    currency = models.CharField(max_length=3)
    reference = models.CharField(max_length=64)
    deposited_on = models.DateField()
    receipt = models.FileField(upload_to=tenant_upload_to("deposit-receipts"), max_length=255)
    receipt_content_type = models.CharField(max_length=64)
    receipt_sha256 = models.CharField(max_length=64)
    status = models.CharField(max_length=20, choices=ClaimStatus.choices, default=ClaimStatus.SUBMITTED)
    first_approved_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    first_approved_at = models.DateTimeField(null=True, blank=True)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    decided_at = models.DateTimeField(null=True, blank=True)
    decision_note = models.CharField(max_length=500, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            # T5: a bank reference or an identical receipt file can only ever be claimed once per tenant.
            models.UniqueConstraint(fields=["tenant", "reference"], name="uniq_deposit_reference_per_tenant"),
            models.UniqueConstraint(fields=["tenant", "receipt_sha256"], name="uniq_deposit_receipt_per_tenant"),
            models.CheckConstraint(condition=models.Q(amount_minor__gt=0), name="deposit_amount_positive"),
        ]
        indexes = [models.Index(fields=["tenant", "status", "created_at"])]


class SubscriptionSource(models.TextChoices):
    DEPOSIT = "deposit", "Approved deposit"
    TRIAL = "trial", "Founder trial"
    COMPENSATION = "compensation", "No-show compensation credit"
    MANUAL = "manual", "Manual adjustment"


class DriverSubscription(TenantScopedModel):
    driver = models.ForeignKey("drivers.DriverProfile", on_delete=models.PROTECT, related_name="subscriptions")
    plan = models.ForeignKey(SubscriptionPlan, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField()
    source = models.CharField(max_length=16, choices=SubscriptionSource.choices)
    claim = models.OneToOneField(DepositClaim, null=True, blank=True, on_delete=models.PROTECT, related_name="subscription")
    is_revoked = models.BooleanField(default=False)

    class Meta:
        ordering = ["-ends_at"]
        indexes = [models.Index(fields=["tenant", "driver", "ends_at"])]
        constraints = [models.CheckConstraint(condition=models.Q(ends_at__gt=models.F("starts_at")), name="subscription_period_valid")]


class LedgerEntryType(models.TextChoices):
    SUBSCRIPTION_PAYMENT = "subscription_payment", "Subscription payment"
    TRIAL_GRANT = "trial_grant", "Trial grant"
    DISCOUNT = "discount", "Renewal discount"
    COMPENSATION_CREDIT = "compensation_credit", "Compensation credit"
    REVERSAL = "reversal", "Reversal"


class SubscriptionLedgerEntry(AppendOnlyMixin, TenantScopedModel):
    """Immutable ledger of everything that changed a driver's paid/credited entitlement."""

    driver = models.ForeignKey("drivers.DriverProfile", on_delete=models.PROTECT, related_name="ledger_entries")
    entry_type = models.CharField(max_length=24, choices=LedgerEntryType.choices)
    amount_minor = models.BigIntegerField(default=0)
    currency = models.CharField(max_length=3)
    days = models.IntegerField(default=0)
    claim = models.ForeignKey(DepositClaim, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    subscription = models.ForeignKey(DriverSubscription, null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    reference = models.CharField(max_length=120, blank=True)
    note = models.CharField(max_length=500, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+")

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["tenant", "driver", "created_at"])]
