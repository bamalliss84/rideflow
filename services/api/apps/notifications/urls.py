from django.urls import path

from . import views

urlpatterns = [
    path("notifications", views.NotificationListView.as_view(), name="notifications"),
    path("notifications/read", views.NotificationMarkReadView.as_view(), name="notifications-read"),
]
