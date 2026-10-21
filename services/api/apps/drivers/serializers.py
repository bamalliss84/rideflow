from rest_framework import serializers

from apps.core.fields import name_field
from apps.core.files import validate_upload

from .models import DocumentType, DriverDocument, DriverProfile, Vehicle


class VehicleSerializer(serializers.ModelSerializer):
    driver_name = name_field("driver.user.full_name")

    class Meta:
        model = Vehicle
        fields = [
            "driver_name",
            "id",
            "plate_number",
            "make",
            "model",
            "color",
            "year",
            "seats",
            "status",
            "is_active",
            "review_note",
            "created_at",
        ]
        read_only_fields = ["id", "status", "review_note", "created_at"]

    def validate_plate_number(self, value):
        value = value.strip().upper()
        qs = Vehicle.objects.filter(plate_number=value)
        if self.instance is not None:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("This plate is already registered with this operator.")
        return value


class DriverDocumentSerializer(serializers.ModelSerializer):
    driver = serializers.UUIDField(source="driver_id", read_only=True)
    driver_name = name_field("driver.user.full_name")
    file = serializers.FileField(write_only=True)
    vehicle_id = serializers.UUIDField(required=False, allow_null=True, write_only=True)

    class Meta:
        model = DriverDocument
        fields = [
            "driver",
            "driver_name",
            "id",
            "doc_type",
            "number",
            "expires_at",
            "file",
            "vehicle_id",
            "vehicle",
            "content_type",
            "status",
            "review_note",
            "created_at",
        ]
        read_only_fields = ["id", "vehicle", "content_type", "status", "review_note", "created_at"]

    def validate(self, attrs):
        content_type, _ext, digest = validate_upload(attrs.get("file"))
        attrs["content_type"] = content_type
        attrs["sha256"] = digest
        vehicle_id = attrs.pop("vehicle_id", None)
        driver = self.context["driver"]
        if vehicle_id:
            vehicle = Vehicle.objects.filter(pk=vehicle_id, driver=driver).first()
            if vehicle is None:
                raise serializers.ValidationError({"vehicle_id": "Unknown vehicle."})
            attrs["vehicle"] = vehicle
        return attrs


class DriverProfileSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(source="user.full_name", read_only=True)
    phone = serializers.CharField(source="user.phone", read_only=True)
    vehicles = VehicleSerializer(many=True, read_only=True)
    documents = DriverDocumentSerializer(many=True, read_only=True)

    class Meta:
        model = DriverProfile
        fields = [
            "id",
            "full_name",
            "phone",
            "status",
            "is_online",
            "online_since",
            "review_note",
            "submitted_at",
            "reviewed_at",
            "vehicles",
            "documents",
            "created_at",
        ]
        read_only_fields = fields


class EligibilitySerializer(serializers.Serializer):
    eligible = serializers.BooleanField()
    reasons = serializers.ListField(child=serializers.CharField())
    subscription_active = serializers.BooleanField()
    status = serializers.CharField()
    is_online = serializers.BooleanField()


class AvailabilitySerializer(serializers.Serializer):
    online = serializers.BooleanField()


class ReviewDecisionSerializer(serializers.Serializer):
    note = serializers.CharField(max_length=500, required=False, allow_blank=True, default="")


class DriverDecisionSerializer(ReviewDecisionSerializer):
    decision = serializers.ChoiceField(choices=["approve", "reject", "suspend", "reinstate"])


class DocumentTypeSerializer(serializers.Serializer):
    doc_type = serializers.ChoiceField(choices=DocumentType.choices)


class AdminDriverSerializer(DriverProfileSerializer):
    user_id = serializers.UUIDField(source="user.id", read_only=True)

    class Meta(DriverProfileSerializer.Meta):
        fields = DriverProfileSerializer.Meta.fields + ["user_id"]
        read_only_fields = fields
