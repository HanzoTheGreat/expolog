package org.expolog.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "org.expolog.app/timer"
        private const val REQ_POST_NOTIFICATIONS = 4102
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startOrUpdate" -> {
                        val sessionKey = call.argument<String>("sessionKey") ?: ""
                        val nextTriggerMs = (call.argument<Number>("nextTriggerMs"))?.toLong() ?: 0L
                        val repeatIntervalMs =
                            (call.argument<Number>("repeatIntervalMs"))?.toLong() ?: 0L

                        if (nextTriggerMs <= 0L) {
                            stopService(Intent(this, TimerForegroundService::class.java))
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(this, TimerForegroundService::class.java).apply {
                            putExtra(TimerForegroundService.EXTRA_SESSION_KEY, sessionKey)
                            putExtra(TimerForegroundService.EXTRA_NEXT_TRIGGER_MS, nextTriggerMs)
                            putExtra(
                                TimerForegroundService.EXTRA_REPEAT_INTERVAL_MS,
                                repeatIntervalMs,
                            )
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }

                    "stop" -> {
                        stopService(Intent(this, TimerForegroundService::class.java))
                        result.success(null)
                    }

                    "testVibrate" -> {
                        TimerForegroundService.triggerHapticPulse(this)
                        result.success(null)
                    }

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                        } else if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            pendingPermissionResult?.success(false)
                            pendingPermissionResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS,
                            )
                        }
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            result.success(pm?.isIgnoringBatteryOptimizations(packageName) ?: false)
                        } else {
                            result.success(true)
                        }
                    }

                    "openAppSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}