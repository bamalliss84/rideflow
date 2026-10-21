from django.conf import settings
from django.db import models

from apps.core.models import TenantScopedModel


class Notification(TenantScopedModel):
    """Persisted per-user hint. `id` is a monotonically increasing cursor for reconnect replay."""

    id = models.BigAutoField(primary_key=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    kind = models.CharField(max_length=60)
    payload = models.JSONField(default=dict)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["id"]
        indexes = [models.Index(fields=["tenant", "user", "id"])]
