from django.contrib import admin

from apps.core.admin import TenantScopedAdmin

from .models import Bid, Ride, RideEvent

for model, columns in (
    (Ride, ("id", "tenant", "status", "version", "created_at")),
    (Bid, ("ride", "tenant", "driver", "amount_minor", "status")),
    (RideEvent, ("ride", "tenant", "seq", "event_type", "created_at")),
):
    admin.site.register(model, type(f"{model.__name__}Admin", (TenantScopedAdmin,), {"list_display": columns}))
