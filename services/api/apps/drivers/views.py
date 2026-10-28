from django.db.models import Q
from django.shortcuts import get_object_or_404
from django_filters import rest_framework as filters
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core import audit
from apps.core.files import private_file_response
from apps.core.filters import TenantFilterSet
from apps.core.idempotency import idempotent
from apps.core.permissions import IsDriver, TenantPermission
from apps.core.views import schema_safe

from . import services
from .models import DriverDocument, DriverProfile, Vehicle
from .serializers import (
    AdminDriverSerializer,
    AvailabilitySerializer,
    DriverDecisionSerializer,
    DriverDocumentSerializer,
    DriverProfileSerializer,
    EligibilitySerializer,
    ReviewDecisionSerializer,
    VehicleSerializer,
)


class DriverMixin:
    permission_classes = [IsDriver]

    def get_driver(self):
        return services.get_driver_for_user(self.request.user)


@extend_schema(tags=["driver"])
class DriverProfileView(DriverMixin, APIView):
    @extend_schema(responses=DriverProfileSerializer)
    def get(self, request):
        return Response(DriverProfileSerializer(self.get_driver()).data)


@extend_schema(tags=["driver"])
class DriverEligibilityView(DriverMixin, APIView):
    @extend_schema(responses=EligibilitySerializer)
    def get(self, request):
        return Response(services.eligibility(self.get_driver()))


@extend_schema(tags=["driver"])
class DriverSubmitView(DriverMixin, APIView):
    @extend_schema(request=None, responses=DriverProfileSerializer)
    def post(self, request):
        driver = services.submit_for_review(self.get_driver(), request=request)
        return Response(DriverProfileSerializer(driver).data)


@extend_schema(tags=["driver"])
class DriverAvailabilityView(DriverMixin, APIView):
    @extend_schema(request=AvailabilitySerializer, responses=EligibilitySerializer)
    @idempotent("driver.availability", required=False)
    def post(self, request):
        serializer = AvailabilitySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        driver = services.set_availability(self.get_driver(), serializer.validated_data["online"], request=request)
        return Response(services.eligibility(driver))


@extend_schema(tags=["driver"])
class DriverVehicleViewSet(DriverMixin, mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    serializer_class = VehicleSerializer
    pagination_class = None

    @schema_safe(Vehicle)
    def get_queryset(self):
        return Vehicle.objects.filter(driver=self.get_driver())

    def perform_create(self, serializer):
        vehicle = serializer.save(driver=self.get_driver())
        audit.record("driver.vehicle_added", request=self.request, target=vehicle)


@extend_schema(tags=["driver"])
class DriverDocumentViewSet(DriverMixin, mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    serializer_class = DriverDocumentSerializer
    parser_classes = [MultiPartParser, FormParser]
    pagination_class = None

    @schema_safe(DriverDocument)
    def get_queryset(self):
        return DriverDocument.objects.filter(driver=self.get_driver())

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        if getattr(self, "swagger_fake_view", False):
            return ctx
        ctx["driver"] = self.get_driver()
        return ctx

    def perform_create(self, serializer):
        document = serializer.save(driver=self.get_driver())
        audit.record("driver.document_uploaded", request=self.request, target=document, data={"doc_type": document.doc_type})

    @extend_schema(responses={(200, "application/octet-stream"): bytes})
    @action(detail=True, methods=["get"])
    def file(self, request, pk=None):
        document = get_object_or_404(self.get_queryset(), pk=pk)
        return private_file_response(document.file, document.content_type)


# ----- tenant administration (review queue) -----


class AdminDriverFilter(TenantFilterSet):
    status = filters.CharFilter()
    is_online = filters.BooleanFilter()
    phone = filters.CharFilter(field_name="user__phone", lookup_expr="icontains")
    q = filters.CharFilter(method="search", label="Name or phone contains")

    def search(self, queryset, name, value):
        return queryset.filter(Q(user__full_name__icontains=value) | Q(user__phone__icontains=value))

    class Meta:
        model = DriverProfile
        fields = ["status", "is_online", "phone", "q"]


@extend_schema(tags=["admin-drivers"])
class AdminDriverViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AdminDriverSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"list": "drivers.view", "retrieve": "drivers.view", "decide": "drivers.review"}
    filterset_class = AdminDriverFilter
    ordering_fields = ["created_at", "submitted_at", "status"]
    ordering = ["-created_at"]

    @schema_safe(DriverProfile)
    def get_queryset(self):
        return DriverProfile.objects.select_related("user").prefetch_related("vehicles", "documents")

    @extend_schema(request=DriverDecisionSerializer, responses=AdminDriverSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.driver.decide")
    def decide(self, request, pk=None):
        serializer = DriverDecisionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        driver = services.review_driver(
            self.get_object(), serializer.validated_data["decision"], request.user, serializer.validated_data["note"], request=request
        )
        return Response(AdminDriverSerializer(driver).data)


class ReviewQueueFilter(TenantFilterSet):
    status = filters.CharFilter()
    # submitted=true: only applications the driver has sent for review (drafts are not reviewable).
    submitted = filters.BooleanFilter(method="filter_submitted")

    class Meta:
        model = DriverDocument
        fields = ["status", "doc_type", "driver"]

    def filter_submitted(self, queryset, name, value):
        from .services import REVIEWABLE_DRIVER_STATUSES

        lookup = {"driver__status__in": REVIEWABLE_DRIVER_STATUSES}
        return queryset.filter(**lookup) if value else queryset.exclude(**lookup)


class VehicleQueueFilter(TenantFilterSet):
    submitted = filters.BooleanFilter(method="filter_submitted")

    class Meta:
        model = Vehicle
        fields = ["status", "driver"]

    def filter_submitted(self, queryset, name, value):
        from .services import REVIEWABLE_DRIVER_STATUSES

        lookup = {"driver__status__in": REVIEWABLE_DRIVER_STATUSES}
        return queryset.filter(**lookup) if value else queryset.exclude(**lookup)


@extend_schema(tags=["admin-drivers"])
class AdminDocumentViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = DriverDocumentSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"*": "drivers.view", "approve": "drivers.review", "reject": "drivers.review"}
    filterset_class = ReviewQueueFilter
    ordering = ["-created_at"]

    @schema_safe(DriverDocument)
    def get_queryset(self):
        return DriverDocument.objects.select_related("driver__user", "vehicle")

    @extend_schema(responses={(200, "application/octet-stream"): bytes})
    @action(detail=True, methods=["get"])
    def file(self, request, pk=None):
        document = self.get_object()
        audit.record("driver.document_viewed", request=request, target=document)
        return private_file_response(document.file, document.content_type)

    @extend_schema(request=ReviewDecisionSerializer, responses=DriverDocumentSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.document.approve")
    def approve(self, request, pk=None):
        doc = services.review_document(self.get_object(), True, request.user, request.data.get("note", ""), request)
        return Response(DriverDocumentSerializer(doc).data)

    @extend_schema(request=ReviewDecisionSerializer, responses=DriverDocumentSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.document.reject")
    def reject(self, request, pk=None):
        doc = services.review_document(self.get_object(), False, request.user, request.data.get("note", ""), request)
        return Response(DriverDocumentSerializer(doc).data)


@extend_schema(tags=["admin-drivers"])
class AdminVehicleViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = VehicleSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"*": "drivers.view", "approve": "drivers.review", "reject": "drivers.review"}
    filterset_class = VehicleQueueFilter
    ordering = ["-created_at"]

    @schema_safe(Vehicle)
    def get_queryset(self):
        return Vehicle.objects.select_related("driver__user")

    @extend_schema(request=ReviewDecisionSerializer, responses=VehicleSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.vehicle.approve")
    def approve(self, request, pk=None):
        vehicle = services.review_vehicle(self.get_object(), True, request.user, request.data.get("note", ""), request)
        return Response(VehicleSerializer(vehicle).data)

    @extend_schema(request=ReviewDecisionSerializer, responses=VehicleSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.vehicle.reject")
    def reject(self, request, pk=None):
        vehicle = services.review_vehicle(self.get_object(), False, request.user, request.data.get("note", ""), request)
        return Response(VehicleSerializer(vehicle).data)
