package com.rideflow.rideflow_driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The channel server pushes use ("rides"): high importance, so a new request or offer pops up like a message.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("rides", getString(R.string.rides_channel), NotificationManager.IMPORTANCE_HIGH)
            channel.description = getString(R.string.rides_channel_description)
            channel.enableVibration(true)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    // Battery savers stop the app with the screen locked: no requests, no location (Infinix/Tecno freeze it within
    // seconds). The app asks for the Android exemption and opens the maker's own screen where there is one.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rideflow/battery").setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> result.success(mapOf("exempt" to isExempt(), "maker" to Build.MANUFACTURER.lowercase()))
                "requestExemption" -> result.success(requestExemption())
                "openMakerSettings" -> result.success(openMakerSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun isExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestExemption(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return tryStart(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))) ||
            tryStart(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    /** The maker's auto-start or battery screen when one is known and present, else the app's own settings page. */
    private fun openMakerSettings(): String {
        for ((pkg, cls) in makerScreens()) {
            if (tryStart(Intent().setComponent(ComponentName(pkg, cls)))) return "maker"
        }
        return if (tryStart(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))) "app" else "none"
    }

    private fun makerScreens(): List<Pair<String, String>> = when (Build.MANUFACTURER.lowercase()) {
        "infinix", "tecno", "itel" -> listOf(
            "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
        )
        "xiaomi", "redmi", "poco" -> listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "huawei", "honor" -> listOf(
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        )
        "oppo", "realme", "oneplus" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
        )
        "vivo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
        )
        else -> emptyList()
    }

    // No resolveActivity check: since Android 11 it can't see other apps' screens, but starting them still works.
    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        false
    }
}
