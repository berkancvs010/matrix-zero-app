package com.zerolog.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
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
        private const val CALL_CHANNEL_ID = "zerolog_calls_v7"
        private const val MESSAGE_CHANNEL_ID = "zerolog_messages_v5"
        private const val CALL_NOTIFICATION_ID = 9001
        private const val MESSAGE_NOTIFICATION_ID = 9002
        private const val CALL_STATUS_NOTIFICATION_ID = 9003
        private const val ACTIVE_CALL_ID_KEY = "flutter.zerolog.active_call_id"

        private var incomingCallPlayer: MediaPlayer? = null
        private var incomingCallVibrator: Vibrator? = null

        fun stopIncomingCallTone() {
            try {
                incomingCallPlayer?.stop()
            } catch (_: Exception) {}

            try {
                incomingCallPlayer?.release()
            } catch (_: Exception) {}

            incomingCallPlayer = null

            try {
                incomingCallVibrator?.cancel()
            } catch (_: Exception) {}

            incomingCallVibrator = null
        }

        fun stopIncomingCallToneAndNotification(context: Context) {
            stopIncomingCallTone()

            try {
                val notifications = NotificationManagerCompat.from(context)
                notifications.cancel(CALL_NOTIFICATION_ID)
                notifications.cancel(CALL_STATUS_NOTIFICATION_ID)
            } catch (_: Exception) {}

            // Remote call termination can arrive while the app is
            // backgrounded/locked. Do not leave a stale pending call.
            try {
                context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )
                    .edit()
                    .remove("flutter.zerolog.pending_call")
                    .remove(ACTIVE_CALL_ID_KEY)
                    .apply()
            } catch (_: Exception) {}
        }
    }

    private fun startIncomingCallTone() {
        stopIncomingCallTone()

        try {
            incomingCallPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                        )
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION
                        )
                        .build()
                )

                setDataSource(
                    this@ZeroLogFirebaseMessagingService,
                    Uri.parse(
                        "android.resource://${packageName}/${R.raw.zerolog_call}"
                    )
                )

                isLooping = true
                setVolume(1.0f, 1.0f)
                prepare()
                start()
            }

            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager =
                    getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }

            incomingCallVibrator = vibrator

            val vibrationAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createWaveform(
                    longArrayOf(
                        0,
                        500,
                        300,
                        500,
                        300,
                        700
                    ),
                    0
                )

                vibrator.vibrate(
                    effect,
                    vibrationAttributes
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(
                    longArrayOf(
                        0,
                        500,
                        300,
                        500,
                        300,
                        700
                    ),
                    0
                )
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFCM",
                "Incoming ringtone failed",
                e
            )
        }
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
            setSound(null, null)
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

        android.util.Log.d(
            "ZeroLogCall",
            "CALL INVITE received by native FCM: " +
                message.data.toString()
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val notificationGranted =
                checkSelfPermission(
                    android.Manifest.permission.POST_NOTIFICATIONS
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED

            android.util.Log.d(
                "ZeroLogCall",
                "POST_NOTIFICATIONS granted=$notificationGranted"
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                val notificationManager =
                    getSystemService(NotificationManager::class.java)

                android.util.Log.d(
                    "ZeroLogCall",
                    "FULL_SCREEN_INTENT allowed=" +
                        notificationManager.canUseFullScreenIntent()
                )
            } catch (e: Exception) {
                android.util.Log.e(
                    "ZeroLogCall",
                    "Unable to check FULL_SCREEN_INTENT",
                    e
                )
            }
        }

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

        val callPrefs = getSharedPreferences(
            "FlutterSharedPreferences",
            MODE_PRIVATE
        )

        val activeCallId = callPrefs
            .getString(ACTIVE_CALL_ID_KEY, "")
            ?.trim()
            .orEmpty()

        if (activeCallId == callId) {
            return
        }

        if (activeCallId.isNotEmpty()) {
            stopIncomingCallTone()
            NotificationManagerCompat.from(this).cancel(
                CALL_NOTIFICATION_ID
            )
        }

        callPrefs
            .edit()
            .putString(ACTIVE_CALL_ID_KEY, callId)
            .apply()

        startIncomingCallTone()

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

        val intent = Intent(this, IncomingCallActivity::class.java).apply {
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

        val pendingIntent = if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        ) {
            val activityOptions = ActivityOptions.makeBasic().apply {
                pendingIntentCreatorBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }

            PendingIntent.getActivity(
                this,
                CALL_NOTIFICATION_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE,
                activityOptions.toBundle()
            )
        } else {
            PendingIntent.getActivity(
                this,
                CALL_NOTIFICATION_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
        }

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
            .setSilent(true)

        try {
            NotificationManagerCompat.from(this).notify(
                CALL_NOTIFICATION_ID,
                builder.build()
            )

            android.util.Log.d(
                "ZeroLogCall",
                "CALL notification posted successfully. " +
                    "id=$CALL_NOTIFICATION_ID"
            )
        } catch (e: SecurityException) {
            android.util.Log.e(
                "ZeroLogFCM",
                "Call notification permission denied",
                e
            )

            stopIncomingCallToneAndNotification(this)
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFCM",
                "Call notification failed",
                e
            )

            stopIncomingCallToneAndNotification(this)
        }
    }

    private fun showCallStatusNotification(message: RemoteMessage) {
        stopIncomingCallToneAndNotification(this)

        try {
            getSharedPreferences(
                "FlutterSharedPreferences",
                MODE_PRIVATE
            )
                .edit()
                .remove("flutter.zerolog.pending_call")
                .apply()
        } catch (_: Exception) {}
    }

    private fun messageNotificationId(message: RemoteMessage): Int {
        val key = (
            message.data["id"]
                ?: message.data["clientMessageId"]
                ?: message.data["from"]
                ?: System.currentTimeMillis().toString()
        ).trim()

        return 9100 + ((key.hashCode() and 0x7fffffff) % 9000)
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

        val prefs = getSharedPreferences(
            "FlutterSharedPreferences",
            MODE_PRIVATE
        )

        val messagePreview = prefs.getBoolean(
            "flutter.zerolog.chat.message_preview",
            true
        )

        val notificationText = if (messagePreview) {
            text
        } else {
            "Yeni bir ZeroLog mesajı"
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            action = "zerolog.message"
            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP

            putExtra(
                "from",
                (
                    message.data["from"]
                        ?: message.data["sender"]
                        ?: sender
                ).trim()
            )
            putExtra(
                "to",
                (
                    message.data["to"]
                        ?: message.data["recipient"]
                        ?: ""
                ).trim()
            )
            putExtra("text", text)
            putExtra(
                "id",
                (
                    message.data["id"]
                        ?: message.data["messageId"]
                        ?: ""
                ).trim()
            )
            putExtra(
                "clientMessageId",
                message.data["clientMessageId"]?.trim().orEmpty()
            )
        }

        val notificationId = messageNotificationId(message)

        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
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
            .setContentText(notificationText)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(notificationText)
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
                notificationId,
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
