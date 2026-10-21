from django.apps import AppConfig
from django.db.backends.signals import connection_created
from django.db.models.signals import post_migrate


class CoreConfig(AppConfig):
    name = "apps.core"
    label = "core"

    def ready(self):
        from . import db, schema  # noqa: F401  (schema registers OpenAPI extensions)

        connection_created.connect(db.on_connection_created, dispatch_uid="rideflow_rls_connection")
        # Runs after all apps have migrated (post_migrate is emitted once per app at the end of `migrate`).
        post_migrate.connect(db.apply_tenant_db_guards, sender=self, dispatch_uid="rideflow_tenant_guards")
