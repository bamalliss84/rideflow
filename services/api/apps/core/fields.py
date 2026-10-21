"""Serializer fields shared across apps: lat/lng points and GeoJSON geometries (SRID 4326)."""

import json

from django.contrib.gis.geos import GEOSException, GEOSGeometry, Point
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers


class LatLngSerializer(serializers.Serializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)


@extend_schema_field(LatLngSerializer)
class PointField(serializers.Field):
    """{"lat": .., "lng": ..} <-> GEOS Point(lng, lat, srid=4326). `precision` rounds output (privacy)."""

    def __init__(self, precision=None, **kwargs):
        self.precision = precision
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        inner = LatLngSerializer(data=data)
        inner.is_valid(raise_exception=True)
        return Point(inner.validated_data["lng"], inner.validated_data["lat"], srid=4326)

    def to_representation(self, value):
        if value is None:
            return None
        lat, lng = value.y, value.x
        if self.precision is not None:
            lat, lng = round(lat, self.precision), round(lng, self.precision)
        return {"lat": lat, "lng": lng}


@extend_schema_field(OpenApiTypes.OBJECT)
class GeoJSONField(serializers.Field):
    def __init__(self, geom_types=("Polygon", "MultiPolygon"), **kwargs):
        self.geom_types = geom_types
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        try:
            geom = GEOSGeometry(json.dumps(data), srid=4326)
        except (GEOSException, ValueError, TypeError):
            raise serializers.ValidationError("Invalid GeoJSON geometry.")
        if geom.geom_type not in self.geom_types:
            raise serializers.ValidationError(f"Geometry type must be one of {', '.join(self.geom_types)}.")
        if not geom.valid:
            raise serializers.ValidationError("Geometry is not valid.")
        return geom

    def to_representation(self, value):
        return json.loads(value.geojson) if value is not None else None


def name_field(source):
    """Read-only human-readable label for a related object (null when the relation is empty)."""
    return serializers.CharField(source=source, read_only=True, allow_null=True)


class MoneySerializer(serializers.Serializer):
    amount_minor = serializers.IntegerField()
    currency = serializers.CharField()
