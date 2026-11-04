"""Push delivery adapters. No provider is configured yet (D040), so this does nothing until one is.

Push is best-effort: the persisted notification and the REST snapshot stay the source of truth (ADR-0004)."""

from django.conf import settings


def send_push(user, kind, payload):
    if settings.PUSH_PROVIDER == "none":
        return
    raise NotImplementedError(f"Unknown push provider: {settings.PUSH_PROVIDER}")
