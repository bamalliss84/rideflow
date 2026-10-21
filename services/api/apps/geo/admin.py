from django.contrib.gis import admin

from apps.core.admin import TenantScopedAdmin

from .models import City, DriverLocation, ServiceArea


@admin.register(City)
class CityAdmin(TenantScopedAdmin, admin.GISModelAdmin):
    list_display = ("name", "tenant", "is_active")


@admin.register(ServiceArea)
class ServiceAreaAdmin(TenantScopedAdmin, admin.GISModelAdmin):
    list_display = ("name", "tenant", "city", "is_active")


@admin.register(DriverLocation)
class DriverLocationAdmin(TenantScopedAdmin):
    list_display = ("driver", "tenant", "server_ts", "accuracy_m")
