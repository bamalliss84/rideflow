from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("me/violations", views.MyViolationViewSet, basename="my-violation")
router.register("me/disputes", views.MyDisputeViewSet, basename="my-dispute")
router.register("admin/violations", views.AdminViolationViewSet, basename="admin-violation")
router.register("admin/enforcement-actions", views.AdminEnforcementViewSet, basename="admin-enforcement")
router.register("admin/appeals", views.AdminAppealViewSet, basename="admin-appeal")
router.register("admin/disputes", views.AdminDisputeViewSet, basename="admin-dispute")
router.register("admin/trust-snapshots", views.AdminTrustSnapshotViewSet, basename="admin-trust-snapshot")

urlpatterns = [
    path("rides/<uuid:ride_id>/rating", views.RideRatingView.as_view(), name="ride-rating"),
    path("rides/<uuid:ride_id>/disputes", views.RideDisputeView.as_view(), name="ride-dispute"),
    path("me/trust", views.MyTrustView.as_view(), name="my-trust"),
    path("driver/rewards", views.DriverRewardsView.as_view(), name="driver-rewards"),
    *router.urls,
]
