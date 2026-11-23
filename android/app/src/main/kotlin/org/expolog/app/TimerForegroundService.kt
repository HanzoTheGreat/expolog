package org.expolog.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class TimerForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "expolog_timer_channel"
        const val NOTIFICATION_ID = 4101

        const val EXTRA_SESSION_KEY = "session_key"
        const val EXTRA_NEXT_TRIGGER_MS = "next_trigger_ms"
        const val EXTRA_REPEAT_INTERVAL_MS = "repeat_interval_ms"

        // Klar unterscheidbarer Doppel-Puls (ms: Pause, Puls, Pause, Puls)
        private val PULSE_PATTERN = longArrayOf(0L, 220L, 140L, 320L)
        private const val MAX_WAKELOCK_MS = 4L * 60L * 60L * 1000L

        fun triggerHapticPulse(context: Context) {
            val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                mgr?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            if (vibrator == null || !vibrator.hasVibrator()) return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val effect = VibrationEffect.createWaveform(PULSE_PATTERN, -1)
                val attrs = VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(effect, attrs)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createWaveform(PULSE_PATTERN, -1)
                @Suppress("DEPRECATION")
                val audioAttrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                @Suppress("DEPRECATION")
                vibrator.vibrate(effect, audioAttrs)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(PULSE_PATTERN, -1)
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var activeSessionKey: String? = null
    private var nextTriggerAtMs: Long = 0L
    private var repeatIntervalMs: Long = 0L
    private var isForegroundStarted: Boolean = false

    private val tickRunnable = Runnable {
        val now = System.currentTimeMillis()
        if (nextTriggerAtMs <= 0L) return@Runnable

        if (now + 250L < nextTriggerAtMs) {
            scheduleNextTick()
            return@Runnable
        }

        triggerHapticPulse(this)

        if (repeatIntervalMs > 0L) {
            while (nextTriggerAtMs <= now + 250L) {
                nextTriggerAtMs += repeatIntervalMs
            }
            updateNotification("Check-in fällig")
            scheduleNextTick()
        } else {
            nextTriggerAtMs = 0L
            updateNotification("Timer abgelaufen")
            releaseWakeLock()
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        val sessionKey = intent.getStringExtra(EXTRA_SESSION_KEY) ?: ""
        val requestedNextMs = intent.getLongExtra(EXTRA_NEXT_TRIGGER_MS, 0L)
        val requestedRepeatMs = intent.getLongExtra(EXTRA_REPEAT_INTERVAL_MS, 0L)

        if (requestedNextMs <= 0L) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Gleicher Stand bereits aktiv -> Timer nicht unnötig zurücksetzen
        if (isForegroundStarted && sessionKey.isNotEmpty() && sessionKey == activeSessionKey) {
            return START_STICKY
        }

        activeSessionKey = sessionKey
        nextTriggerAtMs = requestedNextMs
        repeatIntervalMs = requestedRepeatMs

        val notification = buildNotification("Timer aktiv")
        if (!isForegroundStarted) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isForegroundStarted = true
        } else {
            updateNotification("Timer aktiv")
        }

        acquireWakeLock()
        scheduleNextTick()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickRunnable)
        releaseWakeLock()
        isForegroundStarted = false
        activeSessionKey = null
        nextTriggerAtMs = 0L
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun scheduleNextTick() {
        handler.removeCallbacks(tickRunnable)
        if (nextTriggerAtMs <= 0L) return
        val delayMs = (nextTriggerAtMs - System.currentTimeMillis()).coerceAtLeast(0L)
        handler.postDelayed(tickRunnable, delayMs)
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        val wl = wakeLock ?: pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ExpoLog::TimerWakeLock",
        ).apply {
            setReferenceCounted(false)
            wakeLock = this
        }
        wl.acquire(MAX_WAKELOCK_MS)
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Timer",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Diskreter Status für laufende Timer"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(statusText: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("ExpoLog")
            .setContentText(statusText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateNotification(statusText: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.notify(NOTIFICATION_ID, buildNotification(statusText))
    }
}