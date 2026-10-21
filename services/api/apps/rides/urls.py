from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("rides", views.RideViewSet, basename="ride")
router.register("admin/rides", views.AdminRideViewSet, basename="admin-ride")

urlpatterns = [
    path("driver/ride-offers", views.DriverOffersView.as_view(), name="driver-ride-offers"),
    *router.urls,
]
