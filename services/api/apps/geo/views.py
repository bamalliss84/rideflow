from django.contrib.gis.geos import Point
from django.db import IntegrityError, transaction
from drf_spectacular.utils import extend_schema
from rest_framework import viewsets
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core import audit
from apps.core.exceptions import Conflict
from apps.core.permissions import IsDriver, IsRider, IsTenantMember, TenantPermission
from apps.core.throttling import ScopedTenantThrottle
from apps.core.views import schema_safe
from apps.drivers.services import get_driver_for_user
from apps.tenancy.policy import current_policy

from . import services
from .models import City, SavedPlace, ServiceArea
from .serializers import (
    CityPublicSerializer,
    CitySerializer,
    FareEstimateRequestSerializer,
    FareEstimateSerializer,
    LocationUpdateResultSerializer,
    LocationUpdateSerializer,
    NearbyAdminItemSerializer,
    NearbyPublicSerializer,
    NearbyQuerySerializer,
    RecentPlaceSerializer,
    SavedPlaceSerializer,
    ServiceAreaSerializer,
)

COARSE_DECIMALS = 3  # ~110 m: riders never see exact driver positions before a match (T12)


@extend_schema(tags=["geo"])
class CityListView(APIView):
    permission_classes = [IsTenantMember]

    @extend_schema(responses=CityPublicSerializer(many=True))
    def get(self, request):
        return Response(CityPublicSerializer(City.objects.filter(is_active=True), many=True).data)


@extend_schema(tags=["geo"])
class FareEstimateView(APIView):
    permission_classes = [IsRider]

    @extend_schema(request=FareEstimateRequestSerializer, responses=FareEstimateSerializer)
    def post(self, request):
        serializer = FareEstimateRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        city = services.resolve_city(data["pickup"], data.get("city_id"))
        estimate = services.fare_estimate(data["pickup"], data["dropoff"], current_policy())
        return Response({**estimate, "currency": request.tenant.currency, "city_id": city.pk})


@extend_schema(tags=["geo"])
class NearbyDriversView(APIView):
    permission_classes = [IsRider]

    @extend_schema(parameters=[NearbyQuerySerializer], responses=NearbyPublicSerializer)
    def get(self, request):
        query = NearbyQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        policy = current_policy()
        radius = query.validated_data.get("radius_m") or policy["dispatch.initial_radius_m"]
        point = Point(query.validated_data["lng"], query.validated_data["lat"], srid=4326)
        locations = list(services.nearby_driver_locations(point, radius, policy, limit=50))
        return Response(
            {
                "count": len(locations),
                "radius_m": radius,
                "drivers": [
                    {"lat": round(loc.point.y, COARSE_DECIMALS), "lng": round(loc.point.x, COARSE_DECIMALS)} for loc in locations
                ],
            }
        )


@extend_schema(tags=["driver"])
class DriverLocationView(APIView):
    permission_classes = [IsDriver]
    throttle_classes = [ScopedTenantThrottle]
    throttle_scope = "location"

    @extend_schema(request=LocationUpdateSerializer, responses=LocationUpdateResultSerializer)
    def post(self, request):
        serializer = LocationUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        driver = get_driver_for_user(request.user)
        point = Point(data["lng"], data["lat"], srid=4326)
        location, applied = services.update_driver_location(
            driver, point, data["accuracy_m"], data["device_ts"], data.get("heading"), data.get("speed_mps")
        )
        if applied:
            from apps.rides.services import record_driver_location_evidence

            record_driver_location_evidence(driver, location)
        return Response({"applied": applied, "server_ts": location.server_ts})


# ----- tenant administration -----


@extend_schema(tags=["admin-geo"])
class AdminCityViewSet(viewsets.ModelViewSet):
    serializer_class = CitySerializer
    permission_classes = [TenantPermission]
    required_permissions = {"list": "rides.view", "retrieve": "rides.view", "*": "geo.manage"}
    http_method_names = ["get", "post", "patch", "head", "options"]
    filterset_fields = ["is_active"]

    @schema_safe(City)
    def get_queryset(self):
        return City.objects.all()

    def perform_create(self, serializer):
        audit.record("geo.city_created", request=self.request, target=serializer.save())

    def perform_update(self, serializer):
        audit.record("geo.city_updated", request=self.request, target=serializer.save())


@extend_schema(tags=["admin-geo"])
class AdminServiceAreaViewSet(viewsets.ModelViewSet):
    serializer_class = ServiceAreaSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"list": "rides.view", "retrieve": "rides.view", "*": "geo.manage"}
    http_method_names = ["get", "post", "patch", "head", "options"]
    filterset_fields = ["is_active", "city"]

    @schema_safe(ServiceArea)
    def get_queryset(self):
        return ServiceArea.objects.all()

    def perform_create(self, serializer):
        audit.record("geo.service_area_created", request=self.request, target=serializer.save())

    def perform_update(self, serializer):
        audit.record("geo.service_area_updated", request=self.request, target=serializer.save())


@extend_schema(tags=["admin-geo"])
class AdminNearbyDriversView(APIView):
    permission_classes = [TenantPermission]
    required_permission = "drivers.view"

    @extend_schema(parameters=[NearbyQuerySerializer], responses=NearbyAdminItemSerializer(many=True))
    def get(self, request):
        query = NearbyQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        policy = current_policy()
        radius = query.validated_data.get("radius_m") or policy["dispatch.initial_radius_m"]
        point = Point(query.validated_data["lng"], query.validated_data["lat"], srid=4326)
        locations = services.nearby_driver_locations(point, radius, policy, limit=100)
        return Response(
            [
                {
                    "driver_id": loc.driver_id,
                    "full_name": loc.driver.user.full_name,
                    "distance_m": int(loc.distance.m),
                    "location": {"lat": round(loc.point.y, 5), "lng": round(loc.point.x, 5)},
                    "accuracy_m": loc.accuracy_m,
                    "server_ts": loc.server_ts,
                }
                for loc in locations
            ]
        )


MAX_SAVED_PLACES = 20
RECENT_PLACES = 5


@extend_schema(tags=["rider"])
class SavedPlaceViewSet(viewsets.ModelViewSet):
    permission_classes = [IsRider]
    serializer_class = SavedPlaceSerializer
    pagination_class = None
    lookup_value_regex = "[0-9a-f-]{36}"

    @schema_safe(SavedPlace)
    def get_queryset(self):
        return SavedPlace.objects.filter(user=self.request.user)

    def _save(self, serializer):
        try:
            with transaction.atomic():
                serializer.save(user=self.request.user)
        except IntegrityError:
            raise Conflict("You already saved a place of this kind.", code="place_kind_exists")

    def perform_create(self, serializer):
        if self.get_queryset().count() >= MAX_SAVED_PLACES:
            raise Conflict("You reached the limit of saved places.", code="places_limit")
        self._save(serializer)

    def perform_update(self, serializer):
        self._save(serializer)


@extend_schema(tags=["rider"])
class RecentPlacesView(APIView):
    permission_classes = [IsRider]

    @extend_schema(responses=RecentPlaceSerializer(many=True))
    def get(self, request):
        from apps.rides.models import Ride

        places = {}
        for ride in Ride.objects.filter(rider=request.user).order_by("-created_at")[:30]:
            places.setdefault(ride.dropoff_landmark, ride.dropoff)
            if len(places) == RECENT_PLACES:
                break
        rows = [{"landmark": landmark, "point": point} for landmark, point in places.items()]
        return Response(RecentPlaceSerializer(rows, many=True).data)
