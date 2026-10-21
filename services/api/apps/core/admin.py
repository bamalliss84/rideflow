from django.contrib import admin

from .models import AuditEvent


class TenantScopedAdmin(admin.ModelAdmin):
    """Django admin is internal technical administration only; it reads across tenants explicitly."""

    list_filter = ("tenant",)

    def get_queryset(self, request):
        return self.model.all_tenants.get_queryset()


@admin.register(AuditEvent)
class AuditEventAdmin(admin.ModelAdmin):
    list_display = ("created_at", "tenant", "actor", "action", "target_type", "target_id")
    list_filter = ("action",)
    readonly_fields = [f.name for f in AuditEvent._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
