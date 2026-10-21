from django.contrib import admin

from apps.core.admin import TenantScopedAdmin

from .models import Appeal, Dispute, EnforcementAction, Rating, TrustSnapshot, Violation

for model, columns in (
    (Rating, ("ride", "tenant", "rater_role", "stars", "created_at")),
    (TrustSnapshot, ("user", "tenant", "role", "score", "tier")),
    (Violation, ("subject", "tenant", "kind", "status", "created_at")),
    (EnforcementAction, ("subject", "tenant", "action_type", "status", "ends_at")),
    (Dispute, ("ride", "tenant", "category", "status", "created_at")),
    (Appeal, ("violation", "tenant", "status", "created_at")),
):
    admin.site.register(model, type(f"{model.__name__}Admin", (TenantScopedAdmin,), {"list_display": columns}))
