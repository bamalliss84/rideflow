from django.contrib import admin

from apps.core.admin import TenantScopedAdmin

from .models import DepositAccount, DepositClaim, DriverSubscription, SubscriptionLedgerEntry, SubscriptionPlan

for model, columns in (
    (SubscriptionPlan, ("name", "tenant", "price_minor", "duration_days", "is_trial", "is_active")),
    (DepositAccount, ("bank_name", "tenant", "account_name", "is_active")),
    (DepositClaim, ("reference", "tenant", "driver", "amount_minor", "status")),
    (DriverSubscription, ("driver", "tenant", "starts_at", "ends_at", "source")),
    (SubscriptionLedgerEntry, ("driver", "tenant", "entry_type", "amount_minor", "days", "created_at")),
):
    admin.site.register(model, type(f"{model.__name__}Admin", (TenantScopedAdmin,), {"list_display": columns}))
