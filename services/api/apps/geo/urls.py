from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("admin/cities", views.AdminCityViewSet, basename="admin-city")
router.register("admin/service-areas", views.AdminServiceAreaViewSet, basename="admin-service-area")

urlpatterns = [
    path("cities", views.CityListView.as_view(), name="cities"),
    path("fare-estimate", views.FareEstimateView.as_view(), name="fare-estimate"),
    path("drivers/nearby", views.NearbyDriversView.as_view(), name="drivers-nearby"),
    path("driver/location", views.DriverLocationView.as_view(), name="driver-location"),
    path("admin/drivers-nearby", views.AdminNearbyDriversView.as_view(), name="admin-drivers-nearby"),
    *router.urls,
]
