from django_filters import rest_framework as filters
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.filters import TenantFilterSet
from apps.core.idempotency import idempotent
from apps.core.permissions import IsDriver, IsRiderOrDriver, TenantPermission, request_roles
from apps.core.views import schema_safe

from . import services
from .models import Appeal, Dispute, EnforcementAction, Rating, TrustSnapshot, Violation
from .serializers import (
    AppealCreateSerializer,
    AppealDecisionSerializer,
    AppealSerializer,
    DisputeCreateSerializer,
    DisputeNoteSerializer,
    DisputeResolveSerializer,
    DisputeSerializer,
    EnforcementSerializer,
    NoteSerializer,
    RatingCreateSerializer,
    RatingSerializer,
    RewardEligibilitySerializer,
    RoleQuerySerializer,
    TrustSnapshotSerializer,
    ViolationReviewSerializer,
    ViolationSerializer,
)


def _role_for(request, requested=None):
    roles = request_roles(request)
    if requested:
        if requested not in roles:
            raise PermissionDenied("You do not hold this role.")
        return requested
    return "driver" if "driver" in roles else "rider"


@extend_schema(tags=["trust"])
class RideRatingView(APIView):
    permission_classes = [IsRiderOrDriver]

    @extend_schema(request=RatingCreateSerializer, responses={201: RatingSerializer})
    @idempotent("ride.rating")
    def post(self, request, ride_id):
        serializer = RatingCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        rating = services.rate_ride(ride_id, request.user, **serializer.validated_data)
        return Response(RatingSerializer(rating).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["trust"])
class RideDisputeView(APIView):
    permission_classes = [IsRiderOrDriver]

    @extend_schema(request=DisputeCreateSerializer, responses={201: DisputeSerializer})
    @idempotent("ride.dispute")
    def post(self, request, ride_id):
        serializer = DisputeCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        dispute = services.open_dispute(ride_id, request.user, **serializer.validated_data)
        return Response(DisputeSerializer(dispute).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["trust"])
class MyTrustView(APIView):
    permission_classes = [IsRiderOrDriver]

    @extend_schema(parameters=[RoleQuerySerializer], responses=TrustSnapshotSerializer)
    def get(self, request):
        role = _role_for(request, request.query_params.get("role"))
        return Response(TrustSnapshotSerializer(services.refresh_trust(request.user, role)).data)


@extend_schema(tags=["trust"])
class DriverRewardsView(APIView):
    permission_classes = [IsDriver]

    @extend_schema(responses=RewardEligibilitySerializer)
    def get(self, request):
        return Response(services.reward_eligibility(request.user, "driver"))


@extend_schema(tags=["trust"])
class MyViolationViewSet(viewsets.ReadOnlyModelViewSet):
    permission_classes = [IsRiderOrDriver]
    serializer_class = ViolationSerializer

    @schema_safe(Violation)
    def get_queryset(self):
        return Violation.objects.filter(subject=self.request.user)

    @extend_schema(request=AppealCreateSerializer, responses={201: AppealSerializer})
    @action(detail=True, methods=["post"])
    @idempotent("violation.appeal")
    def appeal(self, request, pk=None):
        serializer = AppealCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        appeal = services.file_appeal(self.get_object(), request.user, serializer.validated_data["reason"])
        return Response(AppealSerializer(appeal).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["trust"])
class MyDisputeViewSet(viewsets.ReadOnlyModelViewSet):
    permission_classes = [IsRiderOrDriver]
    serializer_class = DisputeSerializer

    @schema_safe(Dispute)
    def get_queryset(self):
        return Dispute.objects.filter(opened_by=self.request.user) | Dispute.objects.filter(against=self.request.user)

    @extend_schema(request=NoteSerializer, responses={201: DisputeNoteSerializer})
    @action(detail=True, methods=["post"])
    def notes(self, request, pk=None):
        dispute = self.get_object()
        serializer = NoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        role = dispute.opened_by_role if dispute.opened_by_id == request.user.pk else dispute.against_role
        note = services.add_dispute_note(dispute, request.user, role, serializer.validated_data["note"])
        return Response(DisputeNoteSerializer(note).data, status=status.HTTP_201_CREATED)


# ----- tenant administration -----


class ViolationFilter(TenantFilterSet):
    class Meta:
        model = Violation
        fields = ["status", "kind", "subject", "subject_role", "ride"]


@extend_schema(tags=["admin-trust"])
class AdminViolationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = ViolationSerializer
    permission_classes = [TenantPermission]
    required_permission = "violations.review"
    filterset_class = ViolationFilter
    ordering = ["-created_at"]

    @schema_safe(Violation)
    def get_queryset(self):
        return Violation.objects.all()

    @extend_schema(request=ViolationReviewSerializer, responses=ViolationSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.violation.review")
    def review(self, request, pk=None):
        serializer = ViolationReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        violation, _action = services.review_violation(
            self.get_object(),
            verify=serializer.validated_data["verify"],
            reviewer=request.user,
            note=serializer.validated_data["note"],
            request=request,
        )
        return Response(ViolationSerializer(violation).data)


@extend_schema(tags=["admin-trust"])
class AdminEnforcementViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = EnforcementSerializer
    permission_classes = [TenantPermission]
    required_permissions = {"*": "violations.review", "activate": "enforcement.manage", "revoke": "enforcement.manage"}
    filterset_fields = ["status", "action_type", "subject", "subject_role"]
    ordering = ["-created_at"]

    @schema_safe(EnforcementAction)
    def get_queryset(self):
        return EnforcementAction.objects.all()

    @extend_schema(request=None, responses=EnforcementSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.enforcement.activate")
    def activate(self, request, pk=None):
        return Response(EnforcementSerializer(services.activate_enforcement(self.get_object(), request.user, request)).data)

    @extend_schema(request=NoteSerializer, responses=EnforcementSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.enforcement.revoke")
    def revoke(self, request, pk=None):
        note = request.data.get("note", "")
        return Response(EnforcementSerializer(services.revoke_enforcement(self.get_object(), request.user, note, request)).data)


@extend_schema(tags=["admin-trust"])
class AdminAppealViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AppealSerializer
    permission_classes = [TenantPermission]
    required_permission = "violations.review"
    filterset_fields = ["status", "violation"]
    ordering = ["-created_at"]

    @schema_safe(Appeal)
    def get_queryset(self):
        return Appeal.objects.all()

    @extend_schema(request=AppealDecisionSerializer, responses=AppealSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.appeal.decide")
    def decide(self, request, pk=None):
        serializer = AppealDecisionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        appeal = services.decide_appeal(
            self.get_object(),
            uphold=serializer.validated_data["uphold"],
            reviewer=request.user,
            note=serializer.validated_data["note"],
            request=request,
        )
        return Response(AppealSerializer(appeal).data)


class DisputeFilter(TenantFilterSet):
    created_from = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_to = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="lte")

    class Meta:
        model = Dispute
        fields = ["status", "category", "is_safety", "ride", "created_from", "created_to"]


@extend_schema(tags=["admin-trust"])
class AdminDisputeViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = DisputeSerializer
    permission_classes = [TenantPermission]
    required_permission = "disputes.review"
    filterset_class = DisputeFilter
    ordering_fields = ["created_at", "status"]
    ordering = ["-created_at"]

    @schema_safe(Dispute)
    def get_queryset(self):
        return Dispute.objects.prefetch_related("notes")

    @extend_schema(request=DisputeResolveSerializer, responses=DisputeSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("admin.dispute.resolve")
    def resolve(self, request, pk=None):
        serializer = DisputeResolveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        dispute, _violation = services.resolve_dispute(
            self.get_object(),
            uphold=serializer.validated_data["uphold"],
            reviewer=request.user,
            note=serializer.validated_data["note"],
            violation_kind=serializer.validated_data.get("violation_kind"),
            request=request,
        )
        return Response(DisputeSerializer(dispute).data)

    @extend_schema(request=NoteSerializer, responses={201: DisputeNoteSerializer})
    @action(detail=True, methods=["post"])
    def notes(self, request, pk=None):
        serializer = NoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        note = services.add_dispute_note(self.get_object(), request.user, "staff", serializer.validated_data["note"])
        return Response(DisputeNoteSerializer(note).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["admin-trust"])
class AdminRatingViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = RatingSerializer
    permission_classes = [TenantPermission]
    required_permission = "violations.review"
    filterset_fields = ["ratee_role", "stars", "ride", "ratee"]
    ordering_fields = ["created_at", "stars"]
    ordering = ["-created_at"]

    @schema_safe(Rating)
    def get_queryset(self):
        return Rating.objects.select_related("rater", "ratee")


@extend_schema(tags=["admin-trust"])
class AdminTrustSnapshotViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = TrustSnapshotSerializer
    permission_classes = [TenantPermission]
    required_permission = "reports.view"
    filterset_fields = ["role", "tier", "user"]
    ordering_fields = ["score", "rating_avg", "completed_rides"]
    ordering = ["-score"]

    @schema_safe(TrustSnapshot)
    def get_queryset(self):
        return TrustSnapshot.objects.all()
