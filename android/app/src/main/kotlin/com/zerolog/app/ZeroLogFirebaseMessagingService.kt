package com.zerolog.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.json.JSONObject
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class ZeroLogFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val CALL_CHANNEL_ID = "zerolog_calls_v3"
        private const val MESSAGE_CHANNEL_ID = "zerolog_messages_v2"
        private const val CALL_NOTIFICATION_ID = 9001
        private const val MESSAGE_NOTIFICATION_ID = 9002
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)

        android.util.Log.d(
            "ZeroLogFCM",
            "FCM token refreshed length=${token.length}"
        )

        // Flutter tarafı kapalıyken token yenilenirse token'ı kaybetme.
        // Uygulama bir sonraki açılışta/login işleminde güncel tokenı
        // Flutter -> WebSocket -> server üzerinden tekrar gönderecek.
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        android.util.Log.d(
            "ZeroLogFCM",
            "message received data=${message.data}"
        )

        createChannels()

        val type = message.data["type"] ?: return

        when (type) {
            "callInvite" -> showCallNotification(message)
            "callStatus" -> showCallStatusNotification(message)
            "privateMessage" -> {
                // Mesajlarda notification payload bulunduğunda Android
                // arka planda sistem bildirimi kendisi oluşturur.
                // Data-only gelirse burada da bildirimi üret.
                if (message.notification == null) {
                    showMessageNotification(message)
                }
            }
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)

        val callSound = Uri.parse(
            "android.resource://${packageName}/${R.raw.zerolog_call}"
        )

        val messageSound = Uri.parse(
            "android.resource://${packageName}/${R.raw.zerolog_message}"
        )

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val callChannel = NotificationChannel(
            CALL_CHANNEL_ID,
            "Gelen çağrılar",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "ZeroLog sesli arama bildirimleri"
            setSound(callSound, audioAttributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 300, 500, 300, 700)
            lockscreenVisibility =
                android.app.Notification.VISIBILITY_PUBLIC
        }

        val messageChannel = NotificationChannel(
            MESSAGE_CHANNEL_ID,
            "Mesajlar",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "ZeroLog özel mesaj bildirimleri"
            setSound(messageSound, audioAttributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
            lockscreenVisibility =
                android.app.Notification.VISIBILITY_PUBLIC
        }

        manager.createNotificationChannel(callChannel)
        manager.createNotificationChannel(messageChannel)
    }

    private fun showCallNotification(message: RemoteMessage) {
        val caller = (
            message.data["caller"]
                ?: message.data["from"]
                ?: "ZeroLog"
        ).trim()

        val callee = (
            message.data["callee"]
                ?: message.data["to"]
                ?: ""
        ).trim()

        val callId = (
            message.data["callId"]
                ?: ""
        ).trim()

        if (caller.isEmpty() || callId.isEmpty()) return

        val pendingCall = JSONObject()
            .put("type", "callInvite")
            .put("from", caller)
            .put("to", callee)
            .put("callId", callId)
            .toString()

        getSharedPreferences(
            "FlutterSharedPreferences",
            MODE_PRIVATE
        )
            .edit()
            .putString(
                "flutter.zerolog.pending_call",
                pendingCall
            )
            .apply()

        val intent = Intent(this, MainActivity::class.java).apply {
            action = "zerolog.incoming_call"
            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP

            putExtra("zerolog_call", true)
            putExtra("from", caller)
            putExtra("to", callee)
            putExtra("callId", callId)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            CALL_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(
            this,
            CALL_CHANNEL_ID
        )
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Gelen çağrı")
            .setContentText("$caller sizi arıyor")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setVibrate(longArrayOf(0, 500, 300, 500, 300, 700))
            .setSound(
                Uri.parse(
                    "android.resource://${packageName}/${R.raw.zerolog_call}"
                )
            )

        try {
            NotificationManagerCompat.from(this).notify(
                CALL_NOTIFICATION_ID,
                builder.build()
            )
        } catch (e: SecurityException) {
            android.util.Log.e(
                "ZeroLogFCM",
                "Call notification permission denied",
                e
            )
        }
    }

    private fun showCallStatusNotification(message: RemoteMessage) {
        val title = message.data["title"]
            ?.trim()
            .orEmpty()
            .ifEmpty { "ZeroLog çağrı" }

        val body = message.data["body"]
            ?.trim()
            .orEmpty()

        if (body.isEmpty()) return

        try {
            NotificationManagerCompat
                .from(this)
                .cancel(CALL_NOTIFICATION_ID)

            val builder = NotificationCompat.Builder(
                this,
                CALL_CHANNEL_ID
            )
                .setSmallIcon(applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setVibrate(longArrayOf(0, 500, 300, 500))
                .setSound(
                    Uri.parse(
                        "android.resource://${packageName}/${R.raw.zerolog_call}"
                    )
                )

            NotificationManagerCompat
                .from(this)
                .notify(9003, builder.build())
        } catch (e: SecurityException) {
            android.util.Log.e(
                "ZeroLogFCM",
                "Call status notification denied",
                e
            )
        }
    }

    private fun showMessageNotification(message: RemoteMessage) {
        val sender = (
            message.data["sender"]
                ?: message.data["from"]
                ?: "ZeroLog"
        ).trim()

        val text = (
            message.data["text"]
                ?: message.notification?.body
                ?: ""
        ).trim()

        if (text.isEmpty()) return

        val intent = Intent(this, MainActivity::class.java).apply {
            action = "zerolog.message"
            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            MESSAGE_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(
            this,
            MESSAGE_CHANNEL_ID
        )
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(sender)
            .setContentText(text)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(text)
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVibrate(longArrayOf(0, 250, 150, 250))
            .setSound(
                Uri.parse(
                    "android.resource://${packageName}/${R.raw.zerolog_message}"
                )
            )

        try {
            NotificationManagerCompat.from(this).notify(
                MESSAGE_NOTIFICATION_ID,
                builder.build()
            )
        } catch (e: SecurityException) {
            android.util.Log.e(
                "ZeroLogFCM",
                "Message notification permission denied",
                e
            )
        }
    }
}
