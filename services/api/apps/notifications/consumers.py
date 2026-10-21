"""Per-user hint stream. Protocol (JSON):

server -> {"type": "hello", "cursor": <latest id>}
client -> {"type": "resume", "cursor": <last seen id>}   => server replays missed hints, then "resumed"
client -> {"type": "ping"}                               => {"type": "pong"}
server -> {"type": "hint", "cursor": n, "kind": "...", "payload": {...}}
"""

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

from .services import replay, serialize, user_group


class EventsConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        identity = self.scope.get("rideflow")
        if not identity:
            await self.close(code=4401)
            return
        self.tenant_id = identity["tenant_id"]
        self.user_id = identity["user_id"]
        self.group = user_group(self.tenant_id, self.user_id)
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()
        await self.send_json({"type": "hello", "cursor": await self._latest_cursor()})

    async def disconnect(self, code):
        if getattr(self, "group", None):
            await self.channel_layer.group_discard(self.group, self.channel_name)

    async def receive_json(self, content, **kwargs):
        kind = content.get("type")
        if kind == "ping":
            await self.send_json({"type": "pong"})
        elif kind == "resume":
            try:
                cursor = int(content.get("cursor", 0))
            except (TypeError, ValueError):
                cursor = 0
            items = await self._replay(cursor)
            for item in items:
                await self.send_json({"type": "hint", **item})
            await self.send_json({"type": "resumed", "count": len(items), "has_more": len(items) == 100})
        else:
            await self.send_json({"type": "error", "detail": "unknown message type"})

    async def hint(self, event):
        await self.send_json({"type": "hint", **event["message"]})

    @database_sync_to_async
    def _replay(self, cursor):
        from apps.core.context import system_context

        with system_context():
            return [serialize(n) for n in replay(self.tenant_id, self.user_id, cursor)]

    @database_sync_to_async
    def _latest_cursor(self):
        from apps.core.context import system_context

        from .models import Notification

        with system_context():
            latest = (
                Notification.all_tenants.filter(tenant_id=self.tenant_id, user_id=self.user_id)
                .order_by("-id")
                .values_list("id", flat=True)
                .first()
            )
        return latest or 0
