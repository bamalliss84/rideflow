"""FilterSet base: foreign keys are filtered by UUID value, never through a class-level queryset.

django-filter's default ModelChoiceFilter builds `related_model._default_manager.all()` at import time,
i.e. without tenant context; with fail-closed tenant managers that queryset must never be evaluated.
Filtering by id is then applied to the view's already tenant-scoped queryset.
"""

from django.db import models
from django_filters import rest_framework as filters


class TenantFilterSet(filters.FilterSet):
    @classmethod
    def filter_for_lookup(cls, field, lookup_type):
        if isinstance(field, (models.ForeignKey, models.OneToOneField)) and lookup_type == "exact":
            return filters.UUIDFilter, {}
        return super().filter_for_lookup(field, lookup_type)


class TenantFilterBackend(filters.DjangoFilterBackend):
    filterset_base = TenantFilterSet
