from django.contrib import admin

from apps.core.admin import TenantScopedAdmin

from .models import Tenant, TenantApplication, TenantConfig, TenantMembership


@admin.register(Tenant)
class TenantAdmin(admin.ModelAdmin):
    list_display = ("name", "slug", "status", "currency", "time_zone")
    search_fields = ("name", "slug")


@admin.register(TenantApplication)
class TenantApplicationAdmin(admin.ModelAdmin):
    list_display = ("name", "tenant", "app_type", "client_id", "is_active")
    list_filter = ("app_type", "tenant")


@admin.register(TenantMembership)
class TenantMembershipAdmin(TenantScopedAdmin):
    list_display = ("user", "tenant", "role", "status")


@admin.register(TenantConfig)
class TenantConfigAdmin(TenantScopedAdmin):
    list_display = ("tenant", "version", "effective_from")

    def has_change_permission(self, request, obj=None):
        return False
