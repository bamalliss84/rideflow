from rest_framework import serializers

from .models import User, normalize_phone, phone_validator


class PhoneField(serializers.CharField):
    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", 20)
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        value = normalize_phone(super().to_internal_value(data))
        phone_validator(value)
        return value


class OTPRequestSerializer(serializers.Serializer):
    phone = PhoneField()


class OTPRequestResponseSerializer(serializers.Serializer):
    status = serializers.CharField()
    expires_in = serializers.IntegerField()


class OTPVerifySerializer(serializers.Serializer):
    phone = PhoneField()
    code = serializers.RegexField(r"^\d{4,8}$")
    full_name = serializers.CharField(max_length=120, required=False, allow_blank=True)


class TokenPairSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()


class MembershipSummarySerializer(serializers.Serializer):
    tenant_id = serializers.UUIDField()
    tenant_name = serializers.CharField()
    roles = serializers.ListField(child=serializers.CharField())


class LoginResponseSerializer(TokenPairSerializer):
    user_id = serializers.UUIDField()
    is_new_user = serializers.BooleanField()
    tenant = MembershipSummarySerializer()


class PlatformLoginSerializer(serializers.Serializer):
    phone = PhoneField()
    password = serializers.CharField(write_only=True, style={"input_type": "password"})


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "phone", "full_name", "date_joined"]
        read_only_fields = ["id", "phone", "date_joined"]


class MeSerializer(serializers.Serializer):
    user = UserSerializer()
    scope = serializers.CharField()
    is_platform_admin = serializers.BooleanField()
    mfa = serializers.DictField()
    currency_minor_units = serializers.IntegerField(allow_null=True)
    tenant = MembershipSummarySerializer(allow_null=True)
    permissions = serializers.ListField(child=serializers.CharField())
    driver_profile_id = serializers.UUIDField(allow_null=True)
    currency = serializers.CharField(allow_null=True)
    time_zone = serializers.CharField(allow_null=True)


class MFAChallengeSerializer(serializers.Serializer):
    mfa_required = serializers.BooleanField()
    mfa_token = serializers.CharField()
    mfa_enrolled = serializers.BooleanField()
    expires_in = serializers.IntegerField()
    tenant = MembershipSummarySerializer(allow_null=True, required=False)


class MFATokenSerializer(serializers.Serializer):
    mfa_token = serializers.CharField(max_length=2048)


class MFASetupResponseSerializer(serializers.Serializer):
    secret = serializers.CharField()
    otpauth_uri = serializers.CharField()
    account = serializers.CharField()
    issuer = serializers.CharField()


class MFAVerifySerializer(MFATokenSerializer):
    code = serializers.RegexField(r"^\d{6}$")


class MFASessionSerializer(TokenPairSerializer):
    scope = serializers.ChoiceField(choices=["tenant", "platform"])
    user_id = serializers.UUIDField()
    tenant = MembershipSummarySerializer(allow_null=True)


class AppContextSerializer(serializers.Serializer):
    tenant_name = serializers.CharField()
    app_type = serializers.CharField()
    locale = serializers.CharField()
    tenant_status = serializers.CharField()
