from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("driver/vehicles", views.DriverVehicleViewSet, basename="driver-vehicle")
router.register("driver/documents", views.DriverDocumentViewSet, basename="driver-document")
router.register("admin/drivers", views.AdminDriverViewSet, basename="admin-driver")
router.register("admin/driver-documents", views.AdminDocumentViewSet, basename="admin-driver-document")
router.register("admin/vehicles", views.AdminVehicleViewSet, basename="admin-vehicle")

urlpatterns = [
    path("driver/profile", views.DriverProfileView.as_view(), name="driver-profile"),
    path("driver/eligibility", views.DriverEligibilityView.as_view(), name="driver-eligibility"),
    path("driver/submit", views.DriverSubmitView.as_view(), name="driver-submit"),
    path("driver/availability", views.DriverAvailabilityView.as_view(), name="driver-availability"),
    *router.urls,
]
