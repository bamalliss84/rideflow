from django.utils import timezone
from rest_framework import serializers

from apps.core.fields import GeoJSONField, PointField

from .models import City, ServiceArea


class CitySerializer(serializers.ModelSerializer):
    center = PointField()
    boundary = GeoJSONField(geom_types=("MultiPolygon",), required=False, allow_null=True)

    class Meta:
        model = City
        fields = ["id", "name", "slug", "center", "boundary", "time_zone", "is_active", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_slug(self, value):
        qs = City.objects.filter(slug=value)
        if self.instance is not None:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("Slug already used by another city of this operator.")
        return value


class CityPublicSerializer(serializers.ModelSerializer):
    center = PointField()

    class Meta:
        model = City
        fields = ["id", "name", "slug", "center", "time_zone"]


class ServiceAreaSerializer(serializers.ModelSerializer):
    city_id = serializers.UUIDField()
    area = GeoJSONField(geom_types=("Polygon",))

    class Meta:
        model = ServiceArea
        fields = ["id", "city_id", "name", "area", "is_active", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_city_id(self, value):
        if not City.objects.filter(pk=value).exists():
            raise serializers.ValidationError("Unknown city.")
        return value


class LocationUpdateSerializer(serializers.Serializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    accuracy_m = serializers.FloatField(min_value=0, max_value=10000)
    heading = serializers.FloatField(min_value=0, max_value=360, required=False, allow_null=True)
    speed_mps = serializers.FloatField(min_value=0, max_value=100, required=False, allow_null=True)
    device_ts = serializers.DateTimeField(required=False)

    def validate(self, attrs):
        attrs.setdefault("device_ts", timezone.now())
        return attrs


class LocationUpdateResultSerializer(serializers.Serializer):
    applied = serializers.BooleanField()
    server_ts = serializers.DateTimeField()


class FareEstimateRequestSerializer(serializers.Serializer):
    city_id = serializers.UUIDField(required=False, allow_null=True)
    pickup = PointField()
    dropoff = PointField()


class FareEstimateSerializer(serializers.Serializer):
    distance_m = serializers.IntegerField()
    min_minor = serializers.IntegerField()
    max_minor = serializers.IntegerField()
    currency = serializers.CharField()
    is_estimate = serializers.BooleanField()
    label = serializers.CharField()
    config_version = serializers.IntegerField()
    city_id = serializers.UUIDField()


class NearbyQuerySerializer(serializers.Serializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    radius_m = serializers.IntegerField(min_value=100, max_value=20000, required=False)


class CoarsePointSerializer(serializers.Serializer):
    lat = serializers.FloatField()
    lng = serializers.FloatField()


class NearbyPublicSerializer(serializers.Serializer):
    count = serializers.IntegerField()
    radius_m = serializers.IntegerField()
    drivers = CoarsePointSerializer(many=True)


class NearbyAdminItemSerializer(serializers.Serializer):
    driver_id = serializers.UUIDField()
    full_name = serializers.CharField()
    distance_m = serializers.IntegerField()
    location = CoarsePointSerializer()
    accuracy_m = serializers.FloatField()
    server_ts = serializers.DateTimeField()
