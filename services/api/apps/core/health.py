"""Liveness/readiness probes (no authentication, no tenant data)."""

import redis
from django.conf import settings
from django.db import connection
from django.http import JsonResponse
from django.views.decorators.http import require_GET


@require_GET
def live(request):
    return JsonResponse({"status": "ok"})


def _check_db():
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1, postgis_lib_version()")
        row = cursor.fetchone()
    return {"ok": True, "postgis": row[1]}


def _check_redis():
    client = redis.Redis.from_url(settings.REDIS_URL, socket_connect_timeout=2, socket_timeout=2)
    client.ping()
    return {"ok": True}


@require_GET
def ready(request):
    checks = {}
    for name, check in (("database", _check_db), ("redis", _check_redis)):
        try:
            checks[name] = check()
        except Exception as exc:  # report failure without leaking internals
            checks[name] = {"ok": False, "error": type(exc).__name__}
    healthy = all(c["ok"] for c in checks.values())
    return JsonResponse({"status": "ready" if healthy else "unavailable", "checks": checks}, status=200 if healthy else 503)
