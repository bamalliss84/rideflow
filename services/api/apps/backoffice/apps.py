from django.apps import AppConfig


class BackofficeConfig(AppConfig):
    """Platform (tenant provisioning) and tenant administration APIs consumed by the future Next.js dashboard."""

    name = "apps.backoffice"
    label = "backoffice"
