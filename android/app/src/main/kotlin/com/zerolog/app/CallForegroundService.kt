package com.zerolog.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class CallForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.zerolog.app.action.START_CALL"
        const val ACTION_STOP = "com.zerolog.app.action.STOP_CALL"
        const val EXTRA_VIDEO = "video"
        private const val CHANNEL_ID = "zerolog_active_call"
        private const val NOTIFICATION_ID = 9801
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                ServiceCompat.stopForeground(
                    this,
                    ServiceCompat.STOP_FOREGROUND_REMOVE
                )
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                val video = intent.getBooleanExtra(EXTRA_VIDEO, false)
                startCallForeground(video)
            }
        }

        return START_NOT_STICKY
    }

    private fun startCallForeground(video: Boolean) {
        val title = if (video) {
            "Görüntülü görüşme sürüyor"
        } else {
            "Sesli görüşme sürüyor"
        }

        val notification: Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_zerolog)
                .setContentTitle("ZeroLog")
                .setContentText(title)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (video) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }

            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                type
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Aktif görüşmeler",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Devam eden ZeroLog sesli ve görüntülü görüşmeleri"
            }
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
