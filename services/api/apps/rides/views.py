from django.conf import settings
from django.contrib.gis.geos import Point
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django_filters import rest_framework as filters
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.context import tenant_context
from apps.core.files import private_file_response
from apps.core.filters import TenantFilterSet
from apps.core.idempotency import idempotent
from apps.core.permissions import IsDriver, IsRiderOrDriver, TenantPermission, request_roles
from apps.core.throttling import IPScopedThrottle
from apps.core.views import schema_safe
from apps.drivers.models import DriverProfile
from apps.drivers.services import get_driver_for_user
from apps.tenancy.models import Tenant
from apps.tenancy.policy import current_policy

from . import services
from . import state_machine as sm
from .models import Bid, LocationEvidence, Ride, RideAmendment, RideEvent, TripShare
from .serializers import (
    AdminRideSerializer,
    AmendmentCreateSerializer,
    AmendmentRespondSerializer,
    AmendmentSerializer,
    ArrivalLocationResultSerializer,
    ArrivalLocationSerializer,
    ArriveSerializer,
    BidCreateSerializer,
    BidSerializer,
    CancelSerializer,
    ContactAttemptSerializer,
    DeclineSerializer,
    DriverPositionSerializer,
    EmergencyResponseSerializer,
    EmergencySerializer,
    EventsQuerySerializer,
    HiddenOffersSerializer,
    OptionalVersionSerializer,
    PublicTripSerializer,
    RaisePriceSerializer,
    RideCreateSerializer,
    RideEventSerializer,
    RideSerializer,
    SelectBidSerializer,
    StartSerializer,
    TripShareSerializer,
    VersionSerializer,
    public_trip_data,
)


def _valid(serializer_class, request):
    serializer = serializer_class(data=request.data)
    serializer.is_valid(raise_exception=True)
    return serializer.validated_data


class RideFilter(TenantFilterSet):
    status = filters.MultipleChoiceFilter(choices=Ride._meta.get_field("status").choices)

    class Meta:
        model = Ride
        fields = ["status"]


@extend_schema(tags=["rides"])
class RideViewSet(viewsets.GenericViewSet):
    """Rider and driver ride API. Every mutation requires `Idempotency-Key`; lifecycle changes also require
    `expected_version` (optimistic concurrency, 409 on mismatch)."""

    permission_classes = [IsRiderOrDriver]
    serializer_class = RideSerializer
    filterset_class = RideFilter
    lookup_value_regex = "[0-9a-f-]{36}"

    @schema_safe(Ride)
    def get_queryset(self):
        user = self.request.user
        return (
            Ride.objects.filter(Q(rider=user) | Q(driver__user=user) | Q(candidates__driver__user=user))
            .select_related("driver__user", "rider")
            .distinct()
        )

    def _ride(self, pk):
        return get_object_or_404(self.get_queryset(), pk=pk)

    def _snapshot(self, ride_id, code=status.HTTP_200_OK):
        ride = get_object_or_404(Ride.objects.select_related("driver__user", "rider"), pk=ride_id)
        return Response(RideSerializer(ride, context={"request": self.request}).data, status=code)

    def _require_role(self, role):
        if role not in request_roles(self.request):
            raise PermissionDenied(f"Requires the {role} role.")

    def _driver(self):
        self._require_role("driver")
        return get_driver_for_user(self.request.user)

    # --- read

    def list(self, request):
        queryset = self.filter_queryset(self.get_queryset()).order_by("-created_at")
        page = self.paginate_queryset(queryset)
        return self.get_paginated_response(RideSerializer(page, many=True, context={"request": request}).data)

    def retrieve(self, request, pk=None):
        self._ride(pk)
        services.refresh_timeouts(pk)
        return self._snapshot(pk)

    @extend_schema(parameters=[EventsQuerySerializer], responses=RideEventSerializer(many=True))
    @action(detail=True, methods=["get"])
    def events(self, request, pk=None):
        ride = self._ride(pk)
        if not (ride.rider_id == request.user.pk or (ride.driver_id and ride.driver.user_id == request.user.pk)):
            raise PermissionDenied("Only ride participants can read its event log.")
        query = EventsQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        events = RideEvent.objects.filter(ride=ride, seq__gt=query.validated_data["after_seq"]).order_by("seq")[:200]
        return Response(RideEventSerializer(events, many=True).data)

    # --- rider

    @extend_schema(request=RideCreateSerializer, responses={201: RideSerializer})
    @idempotent("ride.create")
    def create(self, request):
        self._require_role("rider")
        data = _valid(RideCreateSerializer, request)
        ride = services.create_ride(request.user, request=request, **data)
        return self._snapshot(ride.pk, status.HTTP_201_CREATED)

    @extend_schema(responses=BidSerializer(many=True))
    @action(detail=True, methods=["get"], url_path="bids")
    def list_bids(self, request, pk=None):
        self._require_role("rider")
        ride = self._ride(pk)
        if ride.rider_id != request.user.pk:
            raise PermissionDenied("Only the rider sees competing offers.")
        services.refresh_timeouts(pk)
        bids = services.open_bids(ride).order_by("amount_minor", "eta_seconds")
        return Response(BidSerializer(bids, many=True, context={"with_driver": True}).data)

    @extend_schema(request=OptionalVersionSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"], url_path="dispatch")
    @idempotent("ride.dispatch")
    def dispatch_wave(self, request, pk=None):
        self._require_role("rider")
        data = _valid(OptionalVersionSerializer, request)
        services.dispatch_next_wave(pk, request.user, data.get("expected_version"))
        return self._snapshot(pk)

    @extend_schema(request=SelectBidSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.select")
    def select(self, request, pk=None):
        self._require_role("rider")
        data = _valid(SelectBidSerializer, request)
        services.select_bid(pk, request.user, data["bid_id"], data["expected_version"], request=request)
        return self._snapshot(pk)

    @extend_schema(request=CancelSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.cancel")
    def cancel(self, request, pk=None):
        data = _valid(CancelSerializer, request)
        ride = self._ride(pk)
        role = sm.RIDER if ride.rider_id == request.user.pk else sm.DRIVER
        if role == sm.DRIVER:
            self._driver()
        services.cancel_ride(pk, request.user, role, data["expected_version"], data["reason"], data["reason_code"], request=request)
        return self._snapshot(pk)

    @extend_schema(request=RaisePriceSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"], url_path="raise-price")
    @idempotent("ride.raise_price")
    def raise_price(self, request, pk=None):
        self._require_role("rider")
        data = _valid(RaisePriceSerializer, request)
        services.raise_price(pk, request.user, data["expected_version"], data["amount_minor"], request=request)
        return self._snapshot(pk)

    @extend_schema(responses=DriverPositionSerializer)
    @action(detail=True, methods=["get"], url_path="driver-location")
    def driver_location(self, request, pk=None):
        ride = self._ride(pk)
        if ride.rider_id != request.user.pk:
            raise PermissionDenied("Only the rider of this ride can follow its driver.")
        position = services.driver_position(ride, current_policy())
        if position is None:
            raise NotFound("No driver position is available for this ride.", code="driver_location_unavailable")
        return Response(position)

    @extend_schema(request=None, responses={201: TripShareSerializer})
    @action(detail=True, methods=["post"])
    @idempotent("ride.share")
    def share(self, request, pk=None):
        self._require_role("rider")
        token = services.share_token(services.share_trip(pk, request.user))
        base = settings.TRIP_SHARE_BASE_URL.rstrip("/")
        return Response({"token": token, "url": f"{base}/{token}" if base else None}, status=status.HTTP_201_CREATED)

    @extend_schema(responses={204: None})
    @share.mapping.delete
    def stop_sharing(self, request, pk=None):
        self._require_role("rider")
        services.stop_sharing(pk, request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @extend_schema(request=EmergencySerializer, responses=EmergencyResponseSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.emergency")
    def emergency(self, request, pk=None):
        data = _valid(EmergencySerializer, request)
        ride = self._ride(pk)
        role = sm.RIDER if ride.rider_id == request.user.pk else sm.DRIVER
        if role == sm.DRIVER:
            self._driver()
        services.record_emergency(pk, request.user, role, data["location"], request=request)
        return Response({"recorded": True, "emergency_phone": current_policy()["safety.emergency_phone"] or None})

    # --- driver

    @extend_schema(request=BidCreateSerializer, responses={201: BidSerializer})
    @list_bids.mapping.post
    @idempotent("ride.bid")
    def place_bid(self, request, pk=None):
        driver = self._driver()
        data = _valid(BidCreateSerializer, request)
        bid = services.place_bid(pk, driver, request=request, **data)
        return Response(BidSerializer(bid).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=None, responses=BidSerializer)
    @action(detail=True, methods=["post"], url_path=r"bids/(?P<bid_id>[0-9a-f-]{36})/withdraw")
    @idempotent("ride.bid_withdraw")
    def withdraw_bid(self, request, pk=None, bid_id=None):
        bid = services.withdraw_bid(pk, bid_id, self._driver())
        return Response(BidSerializer(bid).data)

    @extend_schema(request=VersionSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.confirm")
    def confirm(self, request, pk=None):
        data = _valid(VersionSerializer, request)
        services.confirm_match(pk, self._driver(), data["expected_version"], request=request)
        return self._snapshot(pk)

    @extend_schema(request=DeclineSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.decline")
    def decline(self, request, pk=None):
        data = _valid(DeclineSerializer, request)
        services.decline_match(pk, self._driver(), data["expected_version"], data["reason"])
        return self._snapshot(pk)

    @extend_schema(request=VersionSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"], url_path="en-route")
    @idempotent("ride.en_route")
    def en_route(self, request, pk=None):
        data = _valid(VersionSerializer, request)
        services.mark_en_route(pk, self._driver(), data["expected_version"])
        return self._snapshot(pk)

    @extend_schema(request=ArriveSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.arrive")
    def arrive(self, request, pk=None):
        data = _valid(ArriveSerializer, request)
        services.mark_arrived(
            pk,
            self._driver(),
            data["expected_version"],
            point=Point(data["lng"], data["lat"], srid=4326) if "lat" in data else None,
            accuracy_m=data.get("accuracy_m"),
            device_ts=data.get("device_ts"),
        )
        return self._snapshot(pk)

    @extend_schema(request=ArrivalLocationSerializer, responses=ArrivalLocationResultSerializer)
    @action(detail=True, methods=["post"], url_path="arrival-location")
    @idempotent("ride.arrival_location")
    def arrival_location(self, request, pk=None):
        data = _valid(ArrivalLocationSerializer, request)
        result = services.add_arrival_location(
            pk,
            self._driver(),
            point=Point(data["lng"], data["lat"], srid=4326),
            accuracy_m=data["accuracy_m"],
            device_ts=data["device_ts"],
        )
        return Response(ArrivalLocationResultSerializer(result).data)

    @extend_schema(request=ContactAttemptSerializer, responses={201: RideEventSerializer})
    @action(detail=True, methods=["post"], url_path="contact-attempts")
    @idempotent("ride.contact_attempt")
    def contact_attempt(self, request, pk=None):
        data = _valid(ContactAttemptSerializer, request)
        event = services.record_contact_attempt(pk, self._driver(), data["method"])
        return Response(RideEventSerializer(event).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=StartSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.start")
    def start(self, request, pk=None):
        data = _valid(StartSerializer, request)
        _, problem = services.start_trip(pk, self._driver(), data["expected_version"], data["start_code"])
        if problem:
            return Response({"code": problem, "detail": "The start code was refused."}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)
        return self._snapshot(pk)

    @extend_schema(request=VersionSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"])
    @idempotent("ride.complete")
    def complete(self, request, pk=None):
        data = _valid(VersionSerializer, request)
        services.complete_trip(pk, self._driver(), data["expected_version"])
        return self._snapshot(pk)

    @extend_schema(request=VersionSerializer, responses=RideSerializer)
    @action(detail=True, methods=["post"], url_path="no-show")
    @idempotent("ride.no_show")
    def no_show(self, request, pk=None):
        data = _valid(VersionSerializer, request)
        services.mark_no_show(pk, self._driver(), data["expected_version"], request=request)
        return self._snapshot(pk)

    # --- both parties

    @extend_schema(request=None, responses=RideSerializer)
    @action(detail=True, methods=["post"], url_path="cash-confirm")
    @idempotent("ride.cash_confirm")
    def cash_confirm(self, request, pk=None):
        ride = self._ride(pk)
        role = sm.RIDER if ride.rider_id == request.user.pk else sm.DRIVER
        services.confirm_cash(pk, request.user, role)
        return self._snapshot(pk)

    @extend_schema(responses=AmendmentSerializer(many=True))
    @action(detail=True, methods=["get"])
    def amendments(self, request, pk=None):
        ride = self._ride(pk)
        return Response(AmendmentSerializer(RideAmendment.objects.filter(ride=ride), many=True).data)

    @extend_schema(request=AmendmentCreateSerializer, responses={201: AmendmentSerializer})
    @amendments.mapping.post
    @idempotent("ride.amendment")
    def propose_amendment(self, request, pk=None):
        data = _valid(AmendmentCreateSerializer, request)
        amendment = services.propose_amendment(pk, request.user, **data)
        return Response(AmendmentSerializer(amendment).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=AmendmentRespondSerializer, responses=AmendmentSerializer)
    @action(detail=True, methods=["post"], url_path=r"amendments/(?P<amendment_id>[0-9a-f-]{36})/respond")
    @idempotent("ride.amendment_respond")
    def respond_amendment(self, request, pk=None, amendment_id=None):
        data = _valid(AmendmentRespondSerializer, request)
        amendment = services.respond_amendment(pk, amendment_id, request.user, data["accept"])
        return Response(AmendmentSerializer(amendment).data)


@extend_schema(tags=["driver"])
class PublicTripView(APIView):
    """What a shared link shows, with no sign-in: never a phone number, and nothing once the trip ends."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [IPScopedThrottle]
    throttle_scope = "public_trip"

    @extend_schema(responses=PublicTripSerializer, tags=["public"])
    def get(self, request, token):
        ids = services.read_share_token(token)
        tenant = Tenant.objects.filter(pk=ids[0]).first() if ids else None
        if tenant is None:
            raise NotFound()
        with tenant_context(tenant):
            share = TripShare.objects.select_related("ride__driver__user").filter(pk=ids[1], revoked_at__isnull=True).first()
            if share is None:
                raise NotFound()
            response = Response(public_trip_data(share.ride, services.driver_position(share.ride, current_policy())))
        response["Cache-Control"] = "no-store"
        return response


class DriverPhotoFileView(APIView):
    """A driver's photo, for the driver and for riders who have an offer or a ride from them (D047)."""

    permission_classes = [IsRiderOrDriver]

    @extend_schema(responses={(200, "application/octet-stream"): bytes})
    def get(self, request, driver_id):
        driver = get_object_or_404(DriverProfile, pk=driver_id)
        user = request.user
        if not (
            driver.user_id == user.pk
            or Ride.objects.filter(rider=user, driver=driver).exists()
            or Bid.objects.filter(ride__rider=user, driver=driver).exists()
        ):
            raise NotFound
        return private_file_response(driver.photo, driver.photo_content_type)


class DriverOffersView(APIView):
    permission_classes = [IsDriver]

    @extend_schema(responses=RideSerializer(many=True))
    def get(self, request):
        driver = get_driver_for_user(request.user)
        rides = services.offers_for_driver(driver).select_related("rider")[:50]
        return Response(RideSerializer(rides, many=True, context={"request": request}).data)


@extend_schema(tags=["driver"])
class DriverOfferHideView(APIView):
    permission_classes = [IsDriver]

    @extend_schema(request=None, responses={204: None})
    def post(self, request, ride_id):
        services.hide_offer(ride_id, get_driver_for_user(request.user))
        return Response(status=status.HTTP_204_NO_CONTENT)

    @extend_schema(request=None, responses={204: None})
    def delete(self, request, ride_id):
        services.unhide_offers(get_driver_for_user(request.user), ride_id=ride_id)
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(tags=["driver"])
class DriverHiddenOffersView(APIView):
    permission_classes = [IsDriver]

    @extend_schema(responses=HiddenOffersSerializer)
    def get(self, request):
        return Response({"count": services.hidden_offer_count(get_driver_for_user(request.user))})

    @extend_schema(request=None, responses={204: None})
    def delete(self, request):
        services.unhide_offers(get_driver_for_user(request.user))
        return Response(status=status.HTTP_204_NO_CONTENT)


# ----- tenant administration -----


class AdminRideFilter(TenantFilterSet):
    status = filters.MultipleChoiceFilter(choices=Ride._meta.get_field("status").choices)
    created_from = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_to = filters.IsoDateTimeFilter(field_name="created_at", lookup_expr="lte")
    rider_phone = filters.CharFilter(field_name="rider__phone", lookup_expr="icontains")

    class Meta:
        model = Ride
        fields = ["status", "city", "driver", "rider", "created_from", "created_to", "rider_phone"]


@extend_schema(tags=["admin-rides"])
class AdminRideViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AdminRideSerializer
    permission_classes = [TenantPermission]
    required_permission = "rides.view"
    filterset_class = AdminRideFilter
    ordering_fields = ["created_at", "completed_at", "agreed_fare_minor", "status"]
    ordering = ["-created_at"]

    @schema_safe(Ride)
    def get_queryset(self):
        return Ride.objects.select_related("rider", "driver__user", "city")

    @extend_schema(responses=RideEventSerializer(many=True))
    @action(detail=True, methods=["get"])
    def events(self, request, pk=None):
        return Response(RideEventSerializer(RideEvent.objects.filter(ride=self.get_object()), many=True).data)

    @extend_schema(responses=BidSerializer(many=True))
    @action(detail=True, methods=["get"])
    def bids(self, request, pk=None):
        ride = self.get_object()
        return Response(BidSerializer(ride.bids.all().order_by("created_at"), many=True, context={"with_driver": True}).data)

    @extend_schema(responses={200: dict})
    @action(detail=True, methods=["get"])
    def evidence(self, request, pk=None):
        ride = self.get_object()
        items = LocationEvidence.objects.filter(ride=ride).order_by("created_at")
        return Response(
            [
                {
                    "kind": e.kind,
                    "lat": e.point.y,
                    "lng": e.point.x,
                    "accuracy_m": e.accuracy_m,
                    "device_ts": e.device_ts,
                    "server_ts": e.created_at,
                }
                for e in items
            ]
        )
