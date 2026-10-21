from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.permissions import IsTenantMember

from .models import Notification
from .services import serialize


class NotificationQuerySerializer(serializers.Serializer):
    after = serializers.IntegerField(min_value=0, required=False, default=0)
    limit = serializers.IntegerField(min_value=1, max_value=200, required=False, default=100)


class NotificationItemSerializer(serializers.Serializer):
    cursor = serializers.IntegerField()
    kind = serializers.CharField()
    payload = serializers.DictField()
    created_at = serializers.DateTimeField()


class NotificationPageSerializer(serializers.Serializer):
    items = NotificationItemSerializer(many=True)
    next_cursor = serializers.IntegerField()
    has_more = serializers.BooleanField()


class MarkReadSerializer(serializers.Serializer):
    up_to = serializers.IntegerField(min_value=0)


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
        Notification.objects.filter(user=request.user, id__lte=serializer.validated_data["up_to"], read_at__isnull=True).update(
            read_at=timezone.now()
        )
        return Response(serializer.validated_data)
