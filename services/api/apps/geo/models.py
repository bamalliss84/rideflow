from django.contrib.gis.db import models

from apps.core.models import TenantScopedModel


class City(TenantScopedModel):
    """A city a tenant operates in. Mukalla is seed data for the pilot tenant, never hardcoded."""

    name = models.CharField(max_length=120)
    slug = models.SlugField(max_length=64)
    center = models.PointField(srid=4326, geography=True)
    boundary = models.MultiPolygonField(srid=4326, null=True, blank=True)
    time_zone = models.CharField(max_length=64, blank=True, help_text="Overrides tenant time zone when set.")
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        constraints = [models.UniqueConstraint(fields=["tenant", "slug"], name="uniq_city_slug_per_tenant")]

    def __str__(self):
        return self.name


class ServiceArea(TenantScopedModel):
    city = models.ForeignKey(City, on_delete=models.PROTECT, related_name="service_areas")
    name = models.CharField(max_length=120)
    area = models.PolygonField(srid=4326)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]


class DriverLocation(TenantScopedModel):
    """Latest known position of a driver (presence). History is kept only as ride evidence."""

    driver = models.OneToOneField("drivers.DriverProfile", on_delete=models.CASCADE, related_name="location")
    point = models.PointField(srid=4326, geography=True)
    accuracy_m = models.FloatField()
    heading = models.FloatField(null=True, blank=True)
    speed_mps = models.FloatField(null=True, blank=True)
    device_ts = models.DateTimeField()
    server_ts = models.DateTimeField()

    class Meta:
        indexes = [models.Index(fields=["tenant", "server_ts"])]
