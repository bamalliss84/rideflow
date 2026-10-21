import contextvars
import logging

request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("rideflow_request_id", default="-")


def get_request_id():
    return request_id_var.get()


class ContextFilter(logging.Filter):
    def filter(self, record):
        from .context import get_current_tenant_id

        record.request_id = request_id_var.get()
        try:
            record.tenant_id = get_current_tenant_id() or "-"
        except Exception:  # pragma: no cover - logging must never fail
            record.tenant_id = "-"
        return True
