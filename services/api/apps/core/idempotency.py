"""Idempotent mutations (ADR-0004).

Clients send `Idempotency-Key` (UUID recommended). The first request with a key runs inside a transaction
together with the insert of its IdempotencyRecord; concurrent duplicates block on the unique index and then
replay the stored response. A different payload with the same key is rejected (422).
Responses >= 500 and raised exceptions roll back, so the client may retry with the same key.
"""

import hashlib
import json
from functools import wraps

from django.core.serializers.json import DjangoJSONEncoder
from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.response import Response

from .context import get_current_tenant_id
from .models import IdempotencyRecord

HEADER = "Idempotency-Key"
MAX_KEY_LENGTH = 128


class _RollbackWith(Exception):
    def __init__(self, response):
        self.response = response


def _canonical(data):
    try:
        if hasattr(data, "dict") and not isinstance(data, dict):
            data = {k: data.getlist(k) for k in data.keys()}
        return json.dumps(data, sort_keys=True, cls=DjangoJSONEncoder, default=str)
    except (TypeError, ValueError):
        return repr(data)


def _error(code, detail, http_status):
    return Response({"code": code, "detail": detail}, status=http_status)


def idempotent(scope, required=True):
    def decorator(func):
        @wraps(func)
        def wrapper(view, request, *args, **kwargs):
            key = request.headers.get(HEADER, "").strip()
            if not key:
                if required:
                    return _error("idempotency_key_required", f"{HEADER} header is required.", 400)
                return func(view, request, *args, **kwargs)
            if len(key) > MAX_KEY_LENGTH:
                return _error("idempotency_key_invalid", f"{HEADER} is too long.", 400)
            full_scope = f"{scope}:{json.dumps(kwargs, sort_keys=True, default=str)}"[:200]
            files = sorted((name, f.size) for name, f in getattr(request, "FILES", {}).items())
            request_hash = hashlib.sha256(f"{full_scope}|{_canonical(request.data)}|{files}".encode()).hexdigest()
            try:
                with transaction.atomic():
                    try:
                        with transaction.atomic():
                            record = IdempotencyRecord.objects.create(
                                tenant_id=get_current_tenant_id(),
                                user=request.user,
                                key=key,
                                scope=full_scope,
                                request_hash=request_hash,
                            )
                    except IntegrityError:
                        existing = IdempotencyRecord.objects.get(user=request.user, key=key)
                        if existing.request_hash != request_hash:
                            return _error(
                                "idempotency_key_reused",
                                f"{HEADER} was already used with a different request.",
                                status.HTTP_422_UNPROCESSABLE_ENTITY,
                            )
                        replay = Response(existing.response_body, status=existing.response_status)
                        replay["Idempotent-Replay"] = "true"
                        return replay
                    response = func(view, request, *args, **kwargs)
                    if response.status_code >= 500:
                        raise _RollbackWith(response)
                    body = json.loads(json.dumps(response.data, cls=DjangoJSONEncoder))
                    record.response_status = response.status_code
                    record.response_body = body
                    record.save(update_fields=["response_status", "response_body"])
                    return response
            except _RollbackWith as rollback:
                return rollback.response

        wrapper.idempotent_scope = scope
        return wrapper

    return decorator
