"""Notifications are persisted first, then hinted over WebSocket after the transaction commits.

Clients treat hints as "something changed": they refetch REST snapshots and replay by cursor on reconnect
(ADR-0004). Push delivery is best-effort; correctness never depends on it.
"""

import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction

from apps.core.context import require_tenant

from .models import Notification

logger = logging.getLogger(__name__)


def user_group(tenant_id, user_id):
    """Channel group namespaced by tenant (ADR-0001 §6). Hex ids keep names within channel-layer limits."""
    return f"t.{str(tenant_id).replace('-', '')}.u.{str(user_id).replace('-', '')}"


def serialize(notification):
    return {
        "cursor": notification.pk,
        "kind": notification.kind,
        "payload": notification.payload,
        "created_at": notification.created_at.isoformat(),
    }


def _send(group, message):
    layer = get_channel_layer()
    if layer is None:
        return
    try:
        async_to_sync(layer.group_send)(group, {"type": "hint", "message": message})
    except Exception:  # hints are best-effort; persisted notification remains for replay
        logger.warning("websocket hint delivery failed for %s", group, exc_info=True)


def notify(user, kind, payload):
    if user is None:
        return None
    tenant = require_tenant()
    notification = Notification.objects.create(user=user, kind=kind, payload=payload)
    group = user_group(tenant.pk, user.pk)
    message = serialize(notification)
    transaction.on_commit(lambda: _send(group, message))
    return notification


def replay(tenant_id, user_id, after_cursor, limit=100):
    return list(Notification.all_tenants.filter(tenant_id=tenant_id, user_id=user_id, id__gt=after_cursor).order_by("id")[:limit])
