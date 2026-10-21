from rest_framework import serializers

from apps.core.files import validate_upload

from .models import DepositAccount, DepositClaim, DriverSubscription, SubscriptionLedgerEntry, SubscriptionPlan


class SubscriptionPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = SubscriptionPlan
        fields = ["id", "code", "name", "price_minor", "duration_days", "is_trial", "is_active", "sort_order"]
        read_only_fields = ["id"]

    def validate_code(self, value):
        qs = SubscriptionPlan.objects.filter(code=value)
        if self.instance is not None:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("Plan code already exists.")
        return value

    def validate(self, attrs):
        if attrs.get("price_minor", 0) < 0 or attrs.get("duration_days", 1) <= 0:
            raise serializers.ValidationError("Price must be >= 0 and duration > 0.")
        return attrs


class DepositAccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = DepositAccount
        fields = ["id", "bank_name", "account_name", "account_number", "instructions", "is_active"]
        read_only_fields = ["id"]


class DepositClaimCreateSerializer(serializers.Serializer):
    plan_id = serializers.UUIDField()
    deposit_account_id = serializers.UUIDField()
    amount_minor = serializers.IntegerField(min_value=1)
    reference = serializers.RegexField(r"^[A-Za-z0-9\-_/ ]{4,64}$")
    deposited_on = serializers.DateField()
    receipt = serializers.FileField()

    def validate(self, attrs):
        attrs["content_type"], _ext, attrs["sha256"] = validate_upload(attrs["receipt"])
        plan = SubscriptionPlan.objects.filter(pk=attrs.pop("plan_id")).first()
        account = DepositAccount.objects.filter(pk=attrs.pop("deposit_account_id")).first()
        if plan is None:
            raise serializers.ValidationError({"plan_id": "Unknown plan."})
        if account is None:
            raise serializers.ValidationError({"deposit_account_id": "Unknown deposit account."})
        attrs["plan"], attrs["deposit_account"] = plan, account
        return attrs


class DepositClaimSerializer(serializers.ModelSerializer):
    plan = SubscriptionPlanSerializer(read_only=True)
    driver_id = serializers.UUIDField(read_only=True)
    driver_name = serializers.CharField(source="driver.user.full_name", read_only=True)

    class Meta:
        model = DepositClaim
        fields = [
            "id",
            "driver_id",
            "driver_name",
            "plan",
            "deposit_account",
            "amount_minor",
            "expected_amount_minor",
            "discount_pct",
            "currency",
            "reference",
            "deposited_on",
            "receipt_content_type",
            "status",
            "first_approved_by",
            "first_approved_at",
            "decided_by",
            "decided_at",
            "decision_note",
            "created_at",
        ]
        read_only_fields = fields


class DriverSubscriptionSerializer(serializers.ModelSerializer):
    plan_name = serializers.CharField(source="plan.name", read_only=True, allow_null=True)

    class Meta:
        model = DriverSubscription
        fields = ["id", "driver", "plan", "plan_name", "starts_at", "ends_at", "source", "is_revoked", "created_at"]
        read_only_fields = fields


class LedgerEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = SubscriptionLedgerEntry
        fields = [
            "id",
            "driver",
            "entry_type",
            "amount_minor",
            "currency",
            "days",
            "claim",
            "subscription",
            "reference",
            "note",
            "created_by",
            "created_at",
        ]
        read_only_fields = fields


class SubscriptionOverviewSerializer(serializers.Serializer):
    entitled = serializers.BooleanField()
    current = DriverSubscriptionSerializer(allow_null=True)
    plans = SubscriptionPlanSerializer(many=True)
    deposit_accounts = DepositAccountSerializer(many=True)
    renewal_discount_pct = serializers.IntegerField()
    recent_claims = DepositClaimSerializer(many=True)


class DecisionNoteSerializer(serializers.Serializer):
    note = serializers.CharField(max_length=500, required=False, allow_blank=True, default="")
