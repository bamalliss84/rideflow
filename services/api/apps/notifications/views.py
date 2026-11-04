from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.permissions import IsTenantMember

from .models import DeviceToken, Notification
from .services import serialize


class NotificationQuerySerializer(serializers.Serializer):
    after = serializers.IntegerField(min_value=0, required=False, default=0)
    limit = serializers.IntegerField(min_value=1, max_value=200, required=False, default=100)


class NotificationItemSerializer(serializers.Serializer):
    cursor = serializers.IntegerField()
    kind = serializers.CharField()
    payload = serializers.DictField()
    created_at = serializers.DateTimeField()
    read = serializers.BooleanField()


class NotificationPageSerializer(serializers.Serializer):
    items = NotificationItemSerializer(many=True)
    next_cursor = serializers.IntegerField()
    has_more = serializers.BooleanField()


class MarkReadSerializer(serializers.Serializer):
    """Mark everything up to a cursor (`up_to`) or exactly one notification (`cursor`)."""

    up_to = serializers.IntegerField(min_value=0, required=False)
    cursor = serializers.IntegerField(min_value=1, required=False)

    def validate(self, attrs):
        if ("up_to" in attrs) == ("cursor" in attrs):
            raise serializers.ValidationError("Provide exactly one of up_to or cursor.")
        return attrs


@extend_schema(tags=["realtime"])
class NotificationListView(APIView):
    """Reconnect/replay endpoint: GET /notifications?after=<cursor> returns hints in cursor order."""

    permission_classes = [IsTenantMember]

    @extend_schema(parameters=[NotificationQuerySerializer], responses=NotificationPageSerializer)
    def get(self, request):
        query = NotificationQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        after, limit = query.validated_data["after"], query.validated_data["limit"]
        items = list(Notification.objects.filter(user=request.user, id__gt=after).order_by("id")[: limit + 1])
        has_more = len(items) > limit
        items = items[:limit]
        return Response(
            {
                "items": [serialize(n) for n in items],
                "next_cursor": items[-1].pk if items else after,
                "has_more": has_more,
            }
        )


@extend_schema(tags=["realtime"])
class NotificationMarkReadView(APIView):
    permission_classes = [IsTenantMember]

    @extend_schema(request=MarkReadSerializer, responses={200: MarkReadSerializer})
    def post(self, request):
        serializer = MarkReadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        rows = Notification.objects.filter(user=request.user, read_at__isnull=True)
        rows = rows.filter(id=data["cursor"]) if "cursor" in data else rows.filter(id__lte=data["up_to"])
        rows.update(read_at=timezone.now())
        return Response(serializer.validated_data)


class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=255)
    platform = serializers.ChoiceField(choices=["android", "ios"])


class DeviceTokenRemoveSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=255)


class DeviceTokenView(APIView):
    permission_classes = [IsTenantMember]

    @extend_schema(request=DeviceTokenSerializer, responses={204: None})
    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        DeviceToken.objects.update_or_create(token=data["token"], defaults={"user": request.user, "platform": data["platform"]})
        return Response(status=204)

    @extend_schema(request=DeviceTokenRemoveSerializer, responses={204: None})
    def delete(self, request):
        serializer = DeviceTokenRemoveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        DeviceToken.objects.filter(user=request.user, token=serializer.validated_data["token"]).delete()
        return Response(status=204)
