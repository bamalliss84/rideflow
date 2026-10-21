from django.contrib import admin

from apps.core.admin import TenantScopedAdmin

from .models import DriverDocument, DriverProfile, Vehicle


@admin.register(DriverProfile)
class DriverProfileAdmin(TenantScopedAdmin):
    list_display = ("user", "tenant", "status", "is_online")


@admin.register(Vehicle)
class VehicleAdmin(TenantScopedAdmin):
    list_display = ("plate_number", "tenant", "driver", "status")


@admin.register(DriverDocument)
class DriverDocumentAdmin(TenantScopedAdmin):
    list_display = ("driver", "tenant", "doc_type", "status", "expires_at")
