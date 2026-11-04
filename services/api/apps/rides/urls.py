from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("rides", views.RideViewSet, basename="ride")
router.register("admin/rides", views.AdminRideViewSet, basename="admin-ride")

urlpatterns = [
    path("public/trips/<str:token>", views.PublicTripView.as_view(), name="public-trip"),
    path("drivers/<uuid:driver_id>/photo", views.DriverPhotoFileView.as_view(), name="driver-photo-file"),
    path("driver/ride-offers", views.DriverOffersView.as_view(), name="driver-ride-offers"),
    path("driver/ride-offers/hidden", views.DriverHiddenOffersView.as_view(), name="driver-hidden-offers"),
    path("driver/ride-offers/<uuid:ride_id>/hide", views.DriverOfferHideView.as_view(), name="driver-offer-hide"),
    *router.urls,
]
