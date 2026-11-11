from django.db.models.signals import post_save
from django.dispatch import receiver

from . import app_config
from .models import Tenant, TenantConfig


@receiver(post_save, sender=Tenant)
def tenant_saved(sender, instance, created, **kwargs):
    if not created:
        app_config.announce(instance)


@receiver(post_save, sender=TenantConfig)
def config_saved(sender, instance, created, **kwargs):
    if created:
        app_config.announce(instance.tenant)
