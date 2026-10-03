package com.revai.revai

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.revai/generation")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "requestPermission" -> {
                            val preferences = getSharedPreferences("revai_notifications", MODE_PRIVATE)
                            if (Build.VERSION.SDK_INT >= 33 &&
                                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                                !preferences.getBoolean("requested", false)) {
                                if (permissionResult != null) {
                                    result.error("permission_pending", "Notification permission is already being requested", null)
                                } else {
                                    permissionResult = result
                                    preferences.edit().putBoolean("requested", true).apply()
                                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4100)
                                }
                            } else {
                                result.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                            }
                        }
                        "start" -> {
                            startForegroundService(Intent(this, GenerationService::class.java))
                            result.success(null)
                        }
                        "update" -> {
                            startService(Intent(this, GenerationService::class.java)
                                .putExtra("title", call.argument<String>("title"))
                                .putExtra("stage", call.argument<String>("stage"))
                                .putExtra("waiting", call.argument<Int>("waiting") ?: 0))
                            result.success(null)
                        }
                        "completed" -> {
                            GenerationService.completed(this,
                                call.argument<String>("title") ?: "Quiz generation",
                                call.argument<Boolean>("success") ?: false)
                            result.success(null)
                        }
                        "stop" -> {
                            stopService(Intent(this, GenerationService::class.java))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("notification_error", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.revai/device_info")
            .setMethodCallHandler { call, result ->
                if (call.method != "getDeviceInfo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val memoryInfo = ActivityManager.MemoryInfo()
                (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memoryInfo)
                val storage = StatFs(Environment.getDataDirectory().absolutePath)
                result.success(mapOf(
                    "sdkInt" to Build.VERSION.SDK_INT,
                    "totalMemory" to memoryInfo.totalMem,
                    "availableStorage" to storage.availableBytes,
                ))
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4100) {
            permissionResult?.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
            permissionResult = null
        }
    }

    override fun onDestroy() {
        permissionResult?.success(false)
        permissionResult = null
        super.onDestroy()
    }
}
