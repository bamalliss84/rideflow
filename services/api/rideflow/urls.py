from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView

from apps.core import health

admin.site.site_header = "RideFlow — internal technical administration"

api_v1 = [
    path("", include("apps.accounts.urls")),
    path("", include("apps.drivers.urls")),
    path("", include("apps.geo.urls")),
    path("", include("apps.subscriptions.urls")),
    path("", include("apps.rides.urls")),
    path("", include("apps.trust.urls")),
    path("", include("apps.notifications.urls")),
    path("", include("apps.backoffice.urls")),
]

urlpatterns = [
    path("health/live", health.live, name="health-live"),
    path("health/ready", health.ready, name="health-ready"),
    path("api/v1/", include(api_v1)),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
    path("api/redoc/", SpectacularRedocView.as_view(url_name="schema"), name="redoc"),
    path("django-admin/", admin.site.urls),
]
