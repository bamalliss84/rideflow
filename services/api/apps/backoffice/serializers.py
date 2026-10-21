from rest_framework import serializers

from apps.accounts.serializers import PhoneField
from apps.core.fields import name_field
from apps.core.models import AuditEvent
from apps.tenancy.models import Role, Tenant, TenantApplication, TenantConfig, TenantMembership


class TenantSerializer(serializers.ModelSerializer):
    currency = serializers.CharField(min_length=3, max_length=3)

    class Meta:
        model = Tenant
        fields = ["id", "name", "slug", "status", "currency", "currency_minor_units", "time_zone", "locale", "created_at"]
        read_only_fields = ["id", "status", "created_at"]

    def validate_currency(self, value):
        value = value.upper()
        if len(value) != 3 or not value.isalpha():
            raise serializers.ValidationError("Use an ISO-4217 code.")
        return value

    def validate_time_zone(self, value):
        import zoneinfo

        if value not in zoneinfo.available_timezones():
            raise serializers.ValidationError("Unknown time zone.")
        return value

    def update(self, instance, validated_data):
        if "currency" in validated_data and validated_data["currency"] != instance.currency:
            raise serializers.ValidationError({"currency": "Currency cannot change after provisioning (ADR-0003)."})
        return super().update(instance, validated_data)


class TenantApplicationSerializer(serializers.ModelSerializer):
    class Meta:
        model = TenantApplication
        fields = ["id", "name", "app_type", "client_id", "is_active", "created_at"]
        read_only_fields = ["id", "client_id", "created_at"]


class TenantAdminCreateSerializer(serializers.Serializer):
    phone = PhoneField()
    full_name = serializers.CharField(max_length=120, required=False, allow_blank=True, default="")
    role = serializers.ChoiceField(choices=[Role.OWNER, Role.ADMIN], default=Role.OWNER)


class MembershipSerializer(serializers.ModelSerializer):
    mfa_enrolled = serializers.SerializerMethodField()
    phone = serializers.CharField(source="user.phone", read_only=True)
    full_name = serializers.CharField(source="user.full_name", read_only=True)
    user_id = serializers.UUIDField(source="user.id", read_only=True)

    class Meta:
        model = TenantMembership
        fields = ["id", "user_id", "phone", "full_name", "role", "status", "display_name", "mfa_enrolled", "created_at"]
        read_only_fields = ["id", "user_id", "phone", "full_name", "role", "created_at"]

    def get_mfa_enrolled(self, obj) -> bool:
        device = getattr(obj.user, "mfa_device", None) if hasattr(obj.user, "mfa_device") else None
        return bool(device and device.confirmed_at)


class MemberInviteSerializer(serializers.Serializer):
    phone = PhoneField()
    full_name = serializers.CharField(max_length=120, required=False, allow_blank=True, default="")
    role = serializers.ChoiceField(choices=Role.choices)


class ConfigVersionSerializer(serializers.ModelSerializer):
    class Meta:
        model = TenantConfig
        fields = ["id", "version", "effective_from", "params", "note", "created_by", "created_at"]
        read_only_fields = fields


class ConfigUpdateSerializer(serializers.Serializer):
    params = serializers.DictField()
    note = serializers.CharField(max_length=240, required=False, allow_blank=True, default="")
    effective_from = serializers.DateTimeField(required=False, allow_null=True)
    replace = serializers.BooleanField(required=False, default=False)


class PolicyParamSerializer(serializers.Serializer):
    key = serializers.CharField()
    default = serializers.JSONField()
    type = serializers.CharField()
    min = serializers.FloatField(allow_null=True)
    max = serializers.FloatField(allow_null=True)
    status = serializers.CharField()
    source = serializers.CharField()


class EffectiveConfigSerializer(serializers.Serializer):
    version = serializers.IntegerField()
    effective = serializers.DictField()
    overrides = serializers.DictField()
    parameters = PolicyParamSerializer(many=True)


class AuditEventSerializer(serializers.ModelSerializer):
    actor_name = name_field("actor.full_name")

    class Meta:
        model = AuditEvent
        fields = ["actor_name", "id", "actor", "actor_roles", "action", "target_type", "target_id", "data", "request_id", "created_at"]
        read_only_fields = fields


class RangeQuerySerializer(serializers.Serializer):
    date_from = serializers.DateTimeField(required=False)
    date_to = serializers.DateTimeField(required=False)


class RiderSerializer(serializers.Serializer):
    id = serializers.UUIDField(help_text="Rider membership id")
    user_id = serializers.UUIDField()
    full_name = serializers.CharField()
    phone = serializers.CharField()
    status = serializers.CharField()
    created_at = serializers.DateTimeField()
    rides_total = serializers.IntegerField()
    rides_completed = serializers.IntegerField()
    last_ride_at = serializers.DateTimeField(allow_null=True)


class RiderDetailSerializer(RiderSerializer):
    trust = serializers.DictField(allow_null=True)
    open_violations = serializers.IntegerField()
    recent_rides = serializers.ListField(child=serializers.DictField())


class PlatformTenantSummarySerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()
    slug = serializers.CharField()
    status = serializers.CharField()
    currency = serializers.CharField()
    created_at = serializers.DateTimeField()
    staff = serializers.IntegerField()
    riders = serializers.IntegerField()
    drivers = serializers.IntegerField()
    drivers_approved = serializers.IntegerField()
    rides_30d = serializers.IntegerField()
    rides_completed_30d = serializers.IntegerField()
    active_driver_subscriptions = serializers.IntegerField()


class PlatformOverviewSerializer(serializers.Serializer):
    generated_at = serializers.DateTimeField()
    tenants = serializers.DictField(child=serializers.IntegerField())
    applications = serializers.IntegerField()
    platform_admins = serializers.IntegerField()
    tenants_created_by_month = serializers.ListField(child=serializers.DictField())
    per_tenant = PlatformTenantSummarySerializer(many=True)
