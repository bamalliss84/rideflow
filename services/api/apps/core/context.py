"""Tenant context for the current request/task.

The current tenant lives in a ContextVar. Every change is mirrored to the PostgreSQL session
(`app.tenant_id`, `app.rls_bypass`) so row-level security enforces the same boundary as the ORM.

DB modes:
  system  - trusted internal code (migrations, management commands, Django admin): RLS bypass on.
  locked  - an API request with no tenant resolved yet: RLS denies every tenant-scoped row.
  tenant  - an API request/task bound to exactly one tenant.
"""

import contextvars
from contextlib import contextmanager
from dataclasses import dataclass


class TenantContextMissing(RuntimeError):
    """Raised when tenant-scoped data is accessed without a tenant context (fail closed)."""


class CrossTenantWrite(RuntimeError):
    """Raised when code tries to save an object belonging to a different tenant than the active one."""


@dataclass(frozen=True)
class ContextState:
    mode: str = "system"
    tenant: object = None


SYSTEM_STATE = ContextState()
# The default is a frozen (immutable) dataclass, so sharing it across contexts is safe.
_state: contextvars.ContextVar[ContextState] = contextvars.ContextVar("rideflow_tenant_state", default=SYSTEM_STATE)


def current_state() -> ContextState:
    return _state.get()


def get_current_tenant():
    return _state.get().tenant


def get_current_tenant_id():
    tenant = _state.get().tenant
    return tenant.pk if tenant is not None else None


def require_tenant():
    tenant = _state.get().tenant
    if tenant is None:
        raise TenantContextMissing("Tenant-scoped data accessed without an active tenant context.")
    return tenant


def _apply(state: ContextState):
    from .db import sync_db_state

    _state.set(state)
    sync_db_state(state)


def set_system():
    _apply(ContextState("system", None))


def set_locked():
    _apply(ContextState("locked", None))


def activate_tenant(tenant):
    _apply(ContextState("tenant", tenant))


def restore(state: ContextState):
    _apply(state)


@contextmanager
def tenant_context(tenant):
    """Run a block bound to `tenant` (ORM filter + RLS), restoring the previous state afterwards."""
    previous = _state.get()
    activate_tenant(tenant)
    try:
        yield tenant
    finally:
        restore(previous)


@contextmanager
def system_context():
    """Run trusted internal code across tenants (RLS bypass). Callers must scope queries explicitly."""
    previous = _state.get()
    set_system()
    try:
        yield
    finally:
        restore(previous)
