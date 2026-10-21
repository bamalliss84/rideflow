from django_filters import rest_framework as filters
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, status, viewsets
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
from apps.drivers.services import get_driver_for_user

from . import services
from .models import DepositAccount, DepositClaim, DriverSubscription, SubscriptionLedgerEntry, SubscriptionPlan
from .serializers import (
    DecisionNoteSerializer,
    DepositAccountSerializer,
    DepositClaimCreateSerializer,
    DepositClaimSerializer,
    DriverSubscriptionSerializer,
    LedgerEntrySerializer,
    SubscriptionOverviewSerializer,
    SubscriptionPlanSerializer,
)


@extend_schema(tags=["driver-subscription"])
class DriverSubscriptionOverviewView(APIView):
    permission_classes = [IsDriver]

    @extend_schema(responses=SubscriptionOverviewSerializer)
    def get(self, request):
        driver = get_driver_for_user(request.user)
        current = services.active_subscription(driver)
        return Response(
            {
                "entitled": current is not None,
                "current": DriverSubscriptionSerializer(current).data if current else None,
                "plans": SubscriptionPlanSerializer(SubscriptionPlan.objects.filter(is_active=True), many=True).data,
                "deposit_accounts": DepositAccountSerializer(DepositAccount.objects.filter(is_active=True), many=True).data,
                "renewal_discount_pct": services.renewal_discount_pct(driver),
                "recent_claims": DepositClaimSerializer(DepositClaim.objects.filter(driver=driver)[:10], many=True).data,
            }
        )


@extend_schema(tags=["driver-subscription"])
class DriverTrialView(APIView):
    permission_classes = [IsDriver]

    @extend_schema(request=None, responses={201: DriverSubscriptionSerializer})
    @idempotent("driver.trial")
    def post(self, request):
        subscription = services.start_trial(get_driver_for_user(request.user), request=request)
        return Response(DriverSubscriptionSerializer(subscription).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["driver-subscription"])
class DriverDepositClaimViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    permission_classes = [IsDriver]
    serializer_class = DepositClaimSerializer
    parser_classes = [MultiPartParser, FormParser]

    @schema_safe(DepositClaim)
    def get_queryset(self):
        return DepositClaim.objects.filter(driver=get_driver_for_user(self.request.user)).select_related("plan")

    @extend_schema(request=DepositClaimCreateSerializer, responses={201: DepositClaimSerializer})
    @idempotent("driver.deposit_claim")
    def create(self, request):
        serializer = DepositClaimCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        claim = services.submit_claim(
            get_driver_for_user(request.user),
            plan=data["plan"],
            deposit_account=data["deposit_account"],
            amount_minor=data["amount_minor"],
            reference=data["reference"],
            deposited_on=data["deposited_on"],
            receipt=data["receipt"],
            content_type=data["content_type"],
            sha256=data["sha256"],
            request=request,
        )
        return Response(DepositClaimSerializer(claim).data, status=status.HTTP_201_CREATED)


# ----- tenant administration -----


@extend_schema(tags=["admin-subscriptions"])
class AdminPlanViewSet(viewsets.ModelViewSet):
    serializer_class = SubscriptionPlanSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"list": "subscriptions.view", "retrieve": "subscriptions.view", "*": "subscriptions.manage"}
    http_method_names = ["get", "post", "patch", "head", "options"]
    pagination_class = None

    @schema_safe(SubscriptionPlan)
    def get_queryset(self):
        return SubscriptionPlan.objects.all()

    def perform_create(self, serializer):
        audit.record("subscription.plan_created", request=self.request, target=serializer.save())

    def perform_update(self, serializer):
        audit.record("subscription.plan_updated", request=self.request, target=serializer.save())


@extend_schema(tags=["admin-subscriptions"])
class AdminDepositAccountViewSet(AdminPlanViewSet):
    serializer_class = DepositAccountSerializer

    @schema_safe(DepositAccount)
    def get_queryset(self):
        return DepositAccount.objects.all()

    def perform_create(self, serializer):
        audit.record("subscription.deposit_account_created", request=self.request, target=serializer.save())

    def perform_update(self, serializer):
        audit.record("subscription.deposit_account_updated", request=self.request, target=serializer.save())


class ClaimFilter(TenantFilterSet):
    created_from = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_to = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="lte")
    reference = filters.CharFilter(lookup_expr="icontains")

    class Meta:
        model = DepositClaim
        fields = ["status", "driver", "plan", "reference", "created_from", "created_to"]


@extend_schema(tags=["admin-subscriptions"])
class AdminDepositClaimViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = DepositClaimSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"*": "subscriptions.view", "approve": "subscriptions.review", "reject": "subscriptions.review"}
    filterset_class = ClaimFilter
    ordering_fields = ["created_at", "amount_minor", "status"]
    ordering = ["-created_at"]

    @schema_safe(DepositClaim)
    def get_queryset(self):
        return DepositClaim.objects.select_related("plan", "driver__user")

    @extend_schema(responses={(200, "application/octet-stream"): bytes})
    @action(detail=True, methods=["get"])
    def receipt(self, request, pk=None):
        claim = self.get_object()
        audit.record("subscription.receipt_viewed", request=request, target=claim)
        return private_file_response(claim.receipt, claim.receipt_content_type)

    @extend_schema(request=DecisionNoteSerializer, responses=DepositClaimSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.claim.approve")
    def approve(self, request, pk=None):
        note = DecisionNoteSerializer(data=request.data)
        note.is_valid(raise_exception=True)
        claim = services.approve_claim(self.get_object(), request.user, note.validated_data["note"], request=request)
        return Response(DepositClaimSerializer(claim).data)

    @extend_schema(request=DecisionNoteSerializer, responses=DepositClaimSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.claim.reject")
    def reject(self, request, pk=None):
        note = DecisionNoteSerializer(data=request.data)
        note.is_valid(raise_exception=True)
        claim = services.reject_claim(self.get_object(), request.user, note.validated_data["note"], request=request)
        return Response(DepositClaimSerializer(claim).data)


@extend_schema(tags=["admin-subscriptions"])
class AdminSubscriptionViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = DriverSubscriptionSerializer
    permission_classes = [TenantPermission]
    required_permission = "subscriptions.view"
    filterset_fields = ["driver", "source", "is_revoked"]
    ordering = ["-ends_at"]

    @schema_safe(DriverSubscription)
    def get_queryset(self):
        return DriverSubscription.objects.select_related("plan")


@extend_schema(tags=["admin-subscriptions"])
class AdminLedgerViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = LedgerEntrySerializer
    permission_classes = [TenantPermission]
    required_permission = "subscriptions.view"
    filterset_fields = ["driver", "entry_type"]
    ordering = ["-created_at"]

    @schema_safe(SubscriptionLedgerEntry)
    def get_queryset(self):
        return SubscriptionLedgerEntry.objects.all()
