from django_filters import rest_framework as filters
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.filters import TenantFilterSet
from apps.core.idempotency import idempotent
from apps.core.models import AuditEvent
from apps.core.permissions import IsPlatformAdmin, TenantPermission, request_roles
from apps.core.views import schema_safe
from apps.tenancy import policy
from apps.tenancy import services as tenancy_services
from apps.tenancy.models import (
    MembershipStatus,
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
    RangeQuerySerializer,
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

    @extend_schema(request=TenantAdminCreateSerializer, responses={201: MembershipSerializer})
    @action(detail=True, methods=["post"])
    @idempotent("platform.tenant_admin")
    def admins(self, request, pk=None):
        serializer = TenantAdminCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        tenant = self.get_object()
        membership = services.create_tenant_admin(tenant, actor=request.user, request=request, **serializer.validated_data)
        from apps.core.context import tenant_context

        with tenant_context(tenant):
            data = MembershipSerializer(membership).data
        return Response(data, status=status.HTTP_201_CREATED)


# ---------------------------------------------------------------- tenant administration


@extend_schema(tags=["admin-tenant"])
class TenantProfileView(APIView):
    permission_classes = [TenantPermission]
    required_permission = "reports.view"

    @extend_schema(responses=TenantSerializer)
    def get(self, request):
        return Response(TenantSerializer(request.tenant).data)


@extend_schema(tags=["admin-tenant"])
class MemberViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = MembershipSerializer
    permission_classes = [TenantPermission]
    required_permission = "members.manage"
    filterset_fields = ["role", "status"]
    ordering = ["-created_at"]

    @schema_safe(TenantMembership)
    def get_queryset(self):
        return TenantMembership.objects.select_related("user")

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
        return AuditEvent.objects.filter(tenant=tenant) if tenant else AuditEvent.objects.none()


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
