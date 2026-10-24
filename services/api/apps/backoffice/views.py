from django.db.models import Count, Max, Q
from django.http import Http404
from django_filters import rest_framework as filters
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.context import tenant_context
from apps.core.filters import TenantFilterSet
from apps.core.idempotency import idempotent
from apps.core.models import AuditEvent
from apps.core.permissions import IsPlatformAdmin, TenantPermission, request_roles
from apps.core.views import schema_safe
from apps.tenancy import policy
from apps.tenancy import services as tenancy_services
from apps.tenancy.models import (
    MembershipStatus,
    Role,
    Tenant,
    TenantApplication,
    TenantConfig,
    TenantMembership,
    TenantStatus,
)

from . import services
from .serializers import (
    AuditEventSerializer,
    ConfigUpdateSerializer,
    ConfigVersionSerializer,
    EffectiveConfigSerializer,
    MemberInviteSerializer,
    MembershipSerializer,
    PlatformOverviewSerializer,
    RangeQuerySerializer,
    RiderDetailSerializer,
    RiderSerializer,
    TenantAdminCreateSerializer,
    TenantApplicationSerializer,
    TenantSerializer,
)

# ---------------------------------------------------------------- platform (RideFlow staff)


@extend_schema(tags=["platform"])
class PlatformTenantViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """Tenant provisioning only. No endpoint here exposes tenant operational data (T2)."""

    serializer_class = TenantSerializer
    permission_classes = [IsPlatformAdmin]
    queryset = Tenant.objects.all()
    filterset_fields = ["status"]
    search_fields = ["name", "slug"]
    http_method_names = ["get", "post", "patch", "head", "options"]

    @extend_schema(request=TenantSerializer, responses={201: TenantSerializer})
    @idempotent("platform.tenant_create")
    def create(self, request):
        serializer = TenantSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        tenant = services.provision_tenant(data=serializer.validated_data, actor=request.user, request=request)
        return Response(TenantSerializer(tenant).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=None, responses=TenantSerializer)
    @action(detail=True, methods=["post"])
    def suspend(self, request, pk=None):
        tenant = services.set_tenant_status(self.get_object(), TenantStatus.SUSPENDED, actor=request.user, request=request)
        return Response(TenantSerializer(tenant).data)

    @extend_schema(request=None, responses=TenantSerializer)
    @action(detail=True, methods=["post"])
    def activate(self, request, pk=None):
        tenant = services.set_tenant_status(self.get_object(), TenantStatus.ACTIVE, actor=request.user, request=request)
        return Response(TenantSerializer(tenant).data)

    @extend_schema(responses=TenantApplicationSerializer(many=True))
    @action(detail=True, methods=["get"])
    def applications(self, request, pk=None):
        apps = TenantApplication.objects.filter(tenant=self.get_object())
        return Response(TenantApplicationSerializer(apps, many=True).data)

    @extend_schema(request=TenantApplicationSerializer, responses={201: TenantApplicationSerializer})
    @applications.mapping.post
    def create_application(self, request, pk=None):
        serializer = TenantApplicationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        app = serializer.save(tenant=self.get_object())
        from apps.core import audit

        audit.record(
            "platform.application_created", request=request, target=app, tenant_id=app.tenant_id, data={"app_type": app.app_type}
        )
        return Response(TenantApplicationSerializer(app).data, status=status.HTTP_201_CREATED)

    @extend_schema(responses=MembershipSerializer(many=True))
    @action(detail=True, methods=["get"])
    def admins(self, request, pk=None):
        """Owner/admin memberships of the tenant (provisioning view; no operational data)."""
        tenant = self.get_object()
        with tenant_context(tenant):
            members = TenantMembership.objects.filter(role__in=["owner", "admin"]).select_related("user", "user__mfa_device")
            data = MembershipSerializer(members.order_by("created_at"), many=True).data
        return Response(data)

    @extend_schema(request=TenantAdminCreateSerializer, responses={201: MembershipSerializer})
    @admins.mapping.post
    @idempotent("platform.tenant_admin")
    def create_admin(self, request, pk=None):
        serializer = TenantAdminCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        tenant = self.get_object()
        membership = services.create_tenant_admin(tenant, actor=request.user, request=request, **serializer.validated_data)
        with tenant_context(tenant):
            data = MembershipSerializer(membership).data
        return Response(data, status=status.HTTP_201_CREATED)

    @extend_schema(request=None, responses=MembershipSerializer)
    @action(detail=True, methods=["post"], url_path=r"admins/(?P<membership_id>[0-9a-f-]{36})/reset-mfa")
    @idempotent("platform.admin_reset_mfa")
    def reset_admin_mfa(self, request, pk=None, membership_id=None):
        tenant = self.get_object()
        with tenant_context(tenant):
            membership = TenantMembership.objects.filter(pk=membership_id, role__in=["owner", "admin"]).first()
            if membership is None:
                raise Http404
            services.reset_member_mfa(membership, actor=request.user, request=request, platform=True)
            data = MembershipSerializer(membership).data
        return Response(data)


@extend_schema(tags=["platform"])
class PlatformOverviewView(APIView):
    """Cross-tenant aggregate counts for RideFlow staff (no tenant records or personal data)."""

    permission_classes = [IsPlatformAdmin]

    @extend_schema(responses=PlatformOverviewSerializer)
    def get(self, request):
        return Response(services.platform_overview())


class PlatformAuditFilter(TenantFilterSet):
    created_from = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_to = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="lte")
    action = filters.CharFilter(lookup_expr="startswith")

    class Meta:
        model = AuditEvent
        fields = ["action", "tenant", "created_from", "created_to"]


@extend_schema(tags=["platform"])
class PlatformAuditViewSet(viewsets.ReadOnlyModelViewSet):
    """Platform-level audit: platform actions and platform-staff logins only (never tenant operations)."""

    serializer_class = AuditEventSerializer
    permission_classes = [IsPlatformAdmin]
    filterset_class = PlatformAuditFilter
    ordering = ["-created_at"]

    def get_queryset(self):
        return AuditEvent.objects.filter(action__startswith="platform.").select_related("actor")


# ---------------------------------------------------------------- tenant administration


@extend_schema(tags=["admin-tenant"])
class TenantProfileView(APIView):
    permission_classes = [TenantPermission]
    required_permission = "reports.view"

    @extend_schema(responses=TenantSerializer)
    def get(self, request):
        return Response(TenantSerializer(request.tenant).data)


class MemberFilter(TenantFilterSet):
    role = filters.MultipleChoiceFilter(choices=Role.choices)

    class Meta:
        model = TenantMembership
        fields = ["role", "status"]


@extend_schema(tags=["admin-tenant"])
class MemberViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = MembershipSerializer
    permission_classes = [TenantPermission]
    required_permission = "members.manage"
    filterset_class = MemberFilter
    ordering = ["-created_at"]

    @schema_safe(TenantMembership)
    def get_queryset(self):
        return TenantMembership.objects.select_related("user", "user__mfa_device")

    @extend_schema(request=MemberInviteSerializer, responses={201: MembershipSerializer})
    @idempotent("admin.member_invite")
    def create(self, request):
        serializer = MemberInviteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        membership = services.invite_member(
            actor=request.user, actor_roles=request_roles(request), request=request, **serializer.validated_data
        )
        return Response(MembershipSerializer(membership).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=None, responses=MembershipSerializer)
    @action(detail=True, methods=["post"])
    def suspend(self, request, pk=None):
        membership = services.set_member_status(
            self.get_object(), MembershipStatus.SUSPENDED, actor=request.user, actor_roles=request_roles(request), request=request
        )
        return Response(MembershipSerializer(membership).data)

    @extend_schema(request=None, responses=MembershipSerializer)
    @action(detail=True, methods=["post"])
    def reactivate(self, request, pk=None):
        membership = services.set_member_status(
            self.get_object(), MembershipStatus.ACTIVE, actor=request.user, actor_roles=request_roles(request), request=request
        )
        return Response(MembershipSerializer(membership).data)

    @extend_schema(request=None, responses=MembershipSerializer)
    @action(detail=True, methods=["post"], url_path="reset-mfa")
    @idempotent("admin.member_reset_mfa")
    def reset_mfa(self, request, pk=None):
        membership = services.reset_member_mfa(self.get_object(), actor=request.user, request=request)
        return Response(MembershipSerializer(membership).data)


class RiderFilter(TenantFilterSet):
    q = filters.CharFilter(method="search", label="Name or phone contains")

    def search(self, queryset, name, value):
        return queryset.filter(Q(user__full_name__icontains=value) | Q(user__phone__icontains=value))

    class Meta:
        model = TenantMembership
        fields = ["status", "q"]


@extend_schema(tags=["admin-tenant"])
class AdminRiderViewSet(viewsets.ReadOnlyModelViewSet):
    """Riders (customers) of the operator with ride counters; detail adds trust profile and recent rides."""

    serializer_class = RiderSerializer
    permission_classes = [TenantPermission]
    required_permission = "rides.view"
    filterset_class = RiderFilter
    ordering_fields = ["created_at", "rides_total", "last_ride_at"]
    ordering = ["-created_at"]

    @schema_safe(TenantMembership)
    def get_queryset(self):
        tenant_id = self.request.tenant.pk
        own = Q(user__rides_as_rider__tenant_id=tenant_id)
        return (
            TenantMembership.objects.filter(role="rider")
            .select_related("user")
            .annotate(
                rides_total=Count("user__rides_as_rider", filter=own, distinct=True),
                rides_completed=Count(
                    "user__rides_as_rider", filter=own & Q(user__rides_as_rider__completed_at__isnull=False), distinct=True
                ),
                last_ride_at=Max("user__rides_as_rider__created_at", filter=own),
            )
        )

    @staticmethod
    def _row(m):
        return {
            "id": m.pk,
            "user_id": m.user_id,
            "full_name": m.user.full_name,
            "phone": m.user.phone,
            "status": m.status,
            "created_at": m.created_at,
            "rides_total": m.rides_total,
            "rides_completed": m.rides_completed,
            "last_ride_at": m.last_ride_at,
        }

    def list(self, request, *args, **kwargs):
        page = self.paginate_queryset(self.filter_queryset(self.get_queryset()))
        return self.get_paginated_response(RiderSerializer([self._row(m) for m in page], many=True).data)

    @extend_schema(responses=RiderDetailSerializer)
    def retrieve(self, request, *args, **kwargs):
        from apps.rides.models import Ride
        from apps.rides.serializers import AdminRideSerializer
        from apps.trust.models import Violation
        from apps.trust.services import public_summary

        membership = self.get_object()
        rides = Ride.objects.filter(rider=membership.user).select_related("rider", "driver__user", "city").order_by("-created_at")[:10]
        data = {
            **self._row(membership),
            "trust": public_summary(membership.user, "rider"),
            "open_violations": Violation.objects.filter(
                subject=membership.user, subject_role="rider", status="pending_review"
            ).count(),
            "recent_rides": AdminRideSerializer(rides, many=True).data,
        }
        return Response(RiderDetailSerializer(data).data)


@extend_schema(tags=["admin-tenant"])
class ConfigView(APIView):
    permission_classes = [TenantPermission]
    required_permissions = {"GET": "reports.view", "POST": "config.manage"}

    def _payload(self):
        snapshot = policy.current_policy()
        latest = TenantConfig.objects.order_by("-version").first()
        return {
            "version": snapshot.version,
            "effective": snapshot.params,
            "overrides": latest.params if latest else {},
            "parameters": policy.describe(),
        }

    @extend_schema(responses=EffectiveConfigSerializer)
    def get(self, request):
        return Response(self._payload())

    @extend_schema(request=ConfigUpdateSerializer, responses={201: ConfigVersionSerializer})
    @idempotent("admin.config")
    def post(self, request):
        serializer = ConfigUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        config = tenancy_services.create_config_version(
            overrides=data["params"],
            user=request.user,
            note=data["note"],
            effective_from=data.get("effective_from"),
            request=request,
            replace=data["replace"],
        )
        return Response(ConfigVersionSerializer(config).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["admin-tenant"])
class ConfigVersionViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = ConfigVersionSerializer
    permission_classes = [TenantPermission]
    required_permission = "reports.view"

    @schema_safe(TenantConfig)
    def get_queryset(self):
        return TenantConfig.objects.order_by("-version")


class AuditFilter(TenantFilterSet):
    created_from = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_to = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="lte")
    action = filters.CharFilter(lookup_expr="startswith")

    class Meta:
        model = AuditEvent
        fields = ["action", "actor", "target_type", "target_id", "created_from", "created_to"]


@extend_schema(tags=["admin-tenant"])
class AuditEventViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AuditEventSerializer
    permission_classes = [TenantPermission]
    required_permission = "audit.view"
    filterset_class = AuditFilter
    ordering = ["-created_at"]

    def get_queryset(self):
        # AuditEvent is not RLS-scoped (platform rows have no tenant) so the tenant filter here is mandatory.
        tenant = getattr(self.request, "tenant", None)
        return AuditEvent.objects.filter(tenant=tenant).select_related("actor") if tenant else AuditEvent.objects.none()


class _ReportView(APIView):
    permission_classes = [TenantPermission]
    required_permission = "reports.view"
    report = None

    @extend_schema(parameters=[RangeQuerySerializer], responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        query = RangeQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(type(self).report(request.tenant, query.validated_data.get("date_from"), query.validated_data.get("date_to")))


@extend_schema(tags=["admin-reports"])
class DashboardView(_ReportView):
    report = staticmethod(services.dashboard_metrics)


@extend_schema(tags=["admin-reports"])
class RidesDailyReportView(_ReportView):
    report = staticmethod(services.rides_daily_report)


@extend_schema(tags=["admin-reports"])
class SubscriptionsReportView(_ReportView):
    report = staticmethod(services.subscriptions_report)
