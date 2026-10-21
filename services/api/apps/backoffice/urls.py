from django.urls import path
from rest_framework.routers import SimpleRouter

from . import views

router = SimpleRouter(trailing_slash=False)
router.register("platform/tenants", views.PlatformTenantViewSet, basename="platform-tenant")
router.register("admin/members", views.MemberViewSet, basename="admin-member")
router.register("admin/riders", views.AdminRiderViewSet, basename="admin-rider")
router.register("platform/audit-events", views.PlatformAuditViewSet, basename="platform-audit")
router.register("admin/config/versions", views.ConfigVersionViewSet, basename="admin-config-version")
router.register("admin/audit-events", views.AuditEventViewSet, basename="admin-audit")

urlpatterns = [
    path("admin/tenant", views.TenantProfileView.as_view(), name="admin-tenant"),
    path("platform/overview", views.PlatformOverviewView.as_view(), name="platform-overview"),
    path("admin/config", views.ConfigView.as_view(), name="admin-config"),
    path("admin/dashboard", views.DashboardView.as_view(), name="admin-dashboard"),
    path("admin/reports/rides-daily", views.RidesDailyReportView.as_view(), name="admin-report-rides"),
    path("admin/reports/subscriptions", views.SubscriptionsReportView.as_view(), name="admin-report-subscriptions"),
    *router.urls,
]
