from functools import wraps


def schema_safe(model):
    """OpenAPI generation instantiates views without a tenant; return an empty queryset there (never real data)."""

    def decorator(get_queryset):
        @wraps(get_queryset)
        def wrapper(self, *args, **kwargs):
            if getattr(self, "swagger_fake_view", False):
                return model.all_tenants.none()
            return get_queryset(self, *args, **kwargs)

        return wrapper

    return decorator
