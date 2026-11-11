package com.rideflow.rideflow_rider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The channel server pushes use ("rides"): high importance, so a new request or offer pops up like a message.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("rides", getString(R.string.rides_channel), NotificationManager.IMPORTANCE_HIGH)
            channel.description = getString(R.string.rides_channel_description)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
