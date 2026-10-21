from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ("phone",)
    list_display = ("phone", "full_name", "is_platform_admin", "is_staff", "is_active")
    search_fields = ("phone", "full_name")
    fieldsets = (
        (None, {"fields": ("phone", "password", "full_name")}),
        ("Access", {"fields": ("is_active", "is_staff", "is_superuser", "is_platform_admin", "groups")}),
    )
    add_fieldsets = ((None, {"classes": ("wide",), "fields": ("phone", "password1", "password2")}),)
    list_filter = ("is_platform_admin", "is_staff", "is_active")
    filter_horizontal = ("groups",)
