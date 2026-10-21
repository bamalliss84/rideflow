from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("driver/deposit-claims", views.DriverDepositClaimViewSet, basename="driver-deposit-claim")
router.register("admin/subscription-plans", views.AdminPlanViewSet, basename="admin-plan")
router.register("admin/deposit-accounts", views.AdminDepositAccountViewSet, basename="admin-deposit-account")
router.register("admin/deposit-claims", views.AdminDepositClaimViewSet, basename="admin-deposit-claim")
router.register("admin/subscriptions", views.AdminSubscriptionViewSet, basename="admin-subscription")
router.register("admin/subscription-ledger", views.AdminLedgerViewSet, basename="admin-ledger")

urlpatterns = [
    path("driver/subscription", views.DriverSubscriptionOverviewView.as_view(), name="driver-subscription"),
    path("driver/subscription/trial", views.DriverTrialView.as_view(), name="driver-trial"),
    *router.urls,
]
