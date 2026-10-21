"""Database-level tenant guards (defense in depth, ADR-0001).

1. Session settings `app.tenant_id` / `app.rls_bypass` mirror the Python tenant context.
2. After every `migrate`, for every tenant-scoped model we idempotently ensure:
   - UNIQUE (tenant_id, id)
   - composite FOREIGN KEY (tenant_id, <fk>) -> parent(tenant_id, id) for every FK between tenant-scoped models
   - ENABLE + FORCE ROW LEVEL SECURITY with a tenant policy
3. Append-only tables get a trigger rejecting UPDATE/DELETE.
"""

import hashlib
import logging

from django.apps import apps as global_apps
from django.db import connection, connections, models

logger = logging.getLogger(__name__)

POLICY_NAME = "rideflow_tenant_isolation"
POLICY_EXPR = (
    "(current_setting('app.rls_bypass', true) = 'on' OR tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)"
)


def _db_values(state):
    if state.mode == "tenant":
        return str(state.tenant.pk), "off"
    if state.mode == "locked":
        return "", "off"
    return "", "on"


def sync_db_state(state, conn=None):
    conn = conn or connection
    if conn.vendor != "postgresql" or conn.connection is None:
        # Not connected yet: on_connection_created applies the current state when it opens.
        return
    tenant_id, bypass = _db_values(state)
    with conn.cursor() as cursor:
        cursor.execute(
            "SELECT set_config('app.tenant_id', %s, false), set_config('app.rls_bypass', %s, false)",
            [tenant_id, bypass],
        )


def on_connection_created(sender, connection, **kwargs):
    """A (re)opened connection inherits the current context instead of silently widening access."""
    from .context import current_state

    if connection.vendor != "postgresql":
        return
    tenant_id, bypass = _db_values(current_state())
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT set_config('app.tenant_id', %s, false), set_config('app.rls_bypass', %s, false)",
            [tenant_id, bypass],
        )


def _name(prefix, *parts):
    raw = "_".join(parts)
    digest = hashlib.sha1(raw.encode()).hexdigest()[:8]
    return f"{prefix}_{raw}"[:50] + f"_{digest}"


def tenant_scoped_models():
    from .models import TenantScopedModel

    return [m for m in global_apps.get_models() if issubclass(m, TenantScopedModel) and m._meta.managed and not m._meta.proxy]


def append_only_tables():
    return [m._meta.db_table for m in global_apps.get_models() if getattr(m, "APPEND_ONLY", False)]


def _constraint_exists(cursor, name):
    cursor.execute("SELECT 1 FROM pg_constraint WHERE conname = %s", [name])
    return cursor.fetchone() is not None


def _table_exists(cursor, table):
    cursor.execute("SELECT to_regclass(%s)", [table])
    return cursor.fetchone()[0] is not None


def apply_tenant_db_guards(sender=None, using="default", **kwargs):
    conn = connections[using]
    if conn.vendor != "postgresql":
        return
    scoped = tenant_scoped_models()
    scoped_set = set(scoped)
    with conn.cursor() as cursor:
        present = [m for m in scoped if _table_exists(cursor, m._meta.db_table)]
        for model in present:
            table = model._meta.db_table
            uniq = _name("tuniq", table)
            if not _constraint_exists(cursor, uniq):
                cursor.execute(f'ALTER TABLE "{table}" ADD CONSTRAINT "{uniq}" UNIQUE ("tenant_id", "id")')
        for model in present:
            table = model._meta.db_table
            for field in model._meta.concrete_fields:
                if not isinstance(field, models.ForeignKey) or field.name == "tenant":
                    continue
                parent = field.related_model
                if parent not in scoped_set:
                    continue
                fk = _name("tfk", table, field.column)
                if not _constraint_exists(cursor, fk):
                    cursor.execute(
                        f'ALTER TABLE "{table}" ADD CONSTRAINT "{fk}" FOREIGN KEY ("tenant_id", "{field.column}") '
                        f'REFERENCES "{parent._meta.db_table}" ("tenant_id", "id") DEFERRABLE INITIALLY DEFERRED'
                    )
        for model in present:
            table = model._meta.db_table
            cursor.execute(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY')
            cursor.execute(f'ALTER TABLE "{table}" FORCE ROW LEVEL SECURITY')
            cursor.execute("SELECT 1 FROM pg_policies WHERE tablename = %s AND policyname = %s", [table, POLICY_NAME])
            if cursor.fetchone() is None:
                cursor.execute(f'CREATE POLICY {POLICY_NAME} ON "{table}" USING {POLICY_EXPR} WITH CHECK {POLICY_EXPR}')
        cursor.execute(
            """
            CREATE OR REPLACE FUNCTION rideflow_forbid_mutation() RETURNS trigger AS $$
            BEGIN
              RAISE EXCEPTION 'append-only table %% cannot be %%', TG_TABLE_NAME, TG_OP;
            END
            $$ LANGUAGE plpgsql
            """.replace("%%", "%")
        )
        for table in append_only_tables():
            if not _table_exists(cursor, table):
                continue
            trigger = _name("appendonly", table)
            cursor.execute("SELECT 1 FROM pg_trigger WHERE tgname = %s", [trigger])
            if cursor.fetchone() is None:
                cursor.execute(
                    f'CREATE TRIGGER "{trigger}" BEFORE UPDATE OR DELETE ON "{table}" '
                    "FOR EACH ROW EXECUTE FUNCTION rideflow_forbid_mutation()"
                )
    logger.info("tenant db guards applied to %d tables", len(present))
