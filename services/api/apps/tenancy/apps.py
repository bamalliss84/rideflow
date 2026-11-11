from django.apps import AppConfig


class TenancyConfig(AppConfig):
    name = "apps.tenancy"
    label = "tenancy"

    def ready(self):
        from . import signals  # noqa: F401
