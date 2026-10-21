import re
import uuid

from . import context
from .logging import request_id_var

_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
SYSTEM_PATH_PREFIXES = ("/django-admin/",)


class RequestIdMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        incoming = request.headers.get("X-Request-ID", "")
        request_id = incoming if _REQUEST_ID_RE.match(incoming) else uuid.uuid4().hex
        request.request_id = request_id
        token = request_id_var.set(request_id)
        try:
            response = self.get_response(request)
        finally:
            request_id_var.reset(token)
        response["X-Request-ID"] = request_id
        return response


class TenantContextMiddleware:
    """Every API request starts 'locked' (RLS denies tenant rows) until authentication binds a tenant.

    Django admin (internal technical administration, staff only) runs in system mode.
    The context is always reset afterwards so pooled connections never leak a tenant.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path.startswith(SYSTEM_PATH_PREFIXES):
            context.set_system()
        else:
            context.set_locked()
        try:
            return self.get_response(request)
        finally:
            context.set_system()
