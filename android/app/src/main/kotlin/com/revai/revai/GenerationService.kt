package com.revai.revai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager

/** Keeps local document generation active while the existing Flutter engine runs. */
class GenerationService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels(this)
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Revai:QuizGeneration")
            .apply { acquire(6 * 60 * 60 * 1000L) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Quiz generation"
        val stage = intent?.getStringExtra("stage") ?: "Preparing your quiz"
        val waiting = intent?.getIntExtra("waiting", 0) ?: 0
        val detail = if (waiting > 0) "$stage · $waiting waiting" else stage
        val notification = builder(this, PROGRESS_CHANNEL, title, detail)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .build()
        startForeground(PROGRESS_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        // The job queue belongs to the running Flutter engine, so never restart
        // an empty service after Android has killed that process.
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        private const val PROGRESS_CHANNEL = "revai_generation_progress"
        private const val RESULT_CHANNEL = "revai_generation_results"
        private const val PROGRESS_ID = 4100
        private var resultId = 4200

        fun createChannels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(
                PROGRESS_CHANNEL, "Quiz generation progress", NotificationManager.IMPORTANCE_LOW
            ))
            manager.createNotificationChannel(NotificationChannel(
                RESULT_CHANNEL, "Quiz generation results", NotificationManager.IMPORTANCE_DEFAULT
            ))
        }

        private fun builder(context: Context, channel: String, title: String, text: String): Notification.Builder {
            val launch = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(context, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            return Notification.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_stat_quiz)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(pending)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
        }

        fun completed(context: Context, title: String, success: Boolean) {
            createChannels(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            if (!manager.areNotificationsEnabled()) return
            val text = if (success) "Quiz saved. Tap to review your questions."
                else "Generation failed. Tap to see the error and retry."
            manager.notify(resultId++, builder(context, RESULT_CHANNEL, title, text)
                .setAutoCancel(true).build())
        }
    }
}
