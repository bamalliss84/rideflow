from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

urlpatterns = [
    path("auth/otp/request", views.OTPRequestView.as_view(), name="otp-request"),
    path("auth/otp/verify", views.OTPVerifyView.as_view(), name="otp-verify"),
    path("auth/platform/login", views.PlatformLoginView.as_view(), name="platform-login"),
    path("auth/token/refresh", TokenRefreshView.as_view(), name="token-refresh"),
    path("auth/logout", views.LogoutView.as_view(), name="logout"),
    path("me", views.MeView.as_view(), name="me"),
]
