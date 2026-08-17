package com.zerolog.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.media.MediaPlayer
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "zerolog/system"
    private val startupPermissionRequestCode = 7401
    private val callPermissionRequestCode = 7402
    private var outgoingCallPlayer: MediaPlayer? = null
    private var outgoingCallAudioManager: AudioManager? = null
    private var outgoingCallPreviousMode: Int? = null
    private var outgoingCallPreviousSpeaker: Boolean? = null
    private var callPermissionResult:
        io.flutter.plugin.common.MethodChannel.Result? = null
    private var startupPermissionResult:
        io.flutter.plugin.common.MethodChannel.Result? = null

    private fun requestFullScreenIntentPermission(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            result.success(true)
            return
        }

        try {
            val notificationManager =
                getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager

            if (notificationManager.canUseFullScreenIntent()) {
                result.success(true)
                return
            }

            val intent = Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)

            // Android 14+ requires the user to explicitly allow
            // USE_FULL_SCREEN_INTENT for call notifications.
            result.success(false)
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Failed to open full-screen intent permission settings",
                e
            )
            result.success(false)
        }
    }

    private fun requestStartupPermissions(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        startupPermissionResult = result

        val permissions = mutableListOf<String>()

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (permissions.isEmpty()) {
            startupPermissionResult = null
            result.success(true)
            return
        }

        requestPermissions(
            permissions.toTypedArray(),
            startupPermissionRequestCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (requestCode == startupPermissionRequestCode) {
            val result = startupPermissionResult
            startupPermissionResult = null

            if (result != null) {
                result.success(true)
            }
        }

        if (requestCode == callPermissionRequestCode) {
            val result = callPermissionResult
            callPermissionResult = null

            if (result != null) {
                val granted = grantResults.isNotEmpty() &&
                    grantResults.all {
                        it == PackageManager.PERMISSION_GRANTED
                    }

                result.success(granted)
            }
        }
    }

    private fun requestCallPermissions(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        callPermissionResult = result

        val permissions = mutableListOf<String>()

        if (
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.RECORD_AUDIO)
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }

        if (permissions.isEmpty()) {
            callPermissionResult = null
            result.success(true)
            return
        }

        requestPermissions(
            permissions.toTypedArray(),
            callPermissionRequestCode
        )
    }

    private fun startOutgoingCallTone() {
        stopOutgoingCallTone()

        try {
            val audioManager =
                getSystemService(AUDIO_SERVICE) as AudioManager

            outgoingCallAudioManager = audioManager
            outgoingCallPreviousMode = audioManager.mode
            outgoingCallPreviousSpeaker = audioManager.isSpeakerphoneOn

            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = false

            outgoingCallPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            AudioAttributes.USAGE_VOICE_COMMUNICATION
                        )
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION
                        )
                        .build()
                )

                setDataSource(
                    this@MainActivity,
                    Uri.parse(
                        "android.resource://${packageName}/${R.raw.zerolog_call}"
                    )
                )

                isLooping = true
                setVolume(0.85f, 0.85f)
                prepare()
                start()
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Outgoing call tone failed",
                e
            )
            stopOutgoingCallTone()
        }
    }

    private fun clearCallLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }

            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            )

            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )

            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Failed to clear call lock-screen state",
                e
            )
        }
    }

    private fun stopOutgoingCallTone() {
        try {
            outgoingCallPlayer?.stop()
        } catch (_: Exception) {}

        try {
            outgoingCallPlayer?.release()
        } catch (_: Exception) {}

        outgoingCallPlayer = null

        try {
            val audioManager = outgoingCallAudioManager

            if (audioManager != null) {
                outgoingCallPreviousMode?.let {
                    audioManager.mode = it
                }

                outgoingCallPreviousSpeaker?.let {
                    audioManager.isSpeakerphoneOn = it
                }
            }
        } catch (_: Exception) {}

        outgoingCallAudioManager = null
        outgoingCallPreviousMode = null
        outgoingCallPreviousSpeaker = null
    }

    private fun persistIncomingCallIntent(incomingIntent: Intent?) {
        if (incomingIntent?.action != "zerolog.incoming_call" &&
            incomingIntent?.getBooleanExtra("zerolog_call", false) != true
        ) {
            return
        }

        val from = incomingIntent.getStringExtra("from")?.trim().orEmpty()
        val to = incomingIntent.getStringExtra("to")?.trim().orEmpty()
        val callId = incomingIntent.getStringExtra("callId")?.trim().orEmpty()

        if (from.isEmpty() || to.isEmpty() || callId.isEmpty()) return

        getSharedPreferences("zerolog_native_call", MODE_PRIVATE)
            .edit()
            .putString("from", from)
            .putString("to", to)
            .putString("callId", callId)
            .apply()
    }

    private fun applyIncomingCallLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }

            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            )

            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )

            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Failed to enable call lock-screen state",
                e
            )
        }
    }

    private fun persistMessageIntent(incomingIntent: Intent?) {
        if (incomingIntent?.action != "zerolog.message") {
            return
        }

        val from = incomingIntent.getStringExtra("from")?.trim().orEmpty()
        val to = incomingIntent.getStringExtra("to")?.trim().orEmpty()
        val text = incomingIntent.getStringExtra("text")?.trim().orEmpty()
        val id = incomingIntent.getStringExtra("id")?.trim().orEmpty()
        val clientMessageId =
            incomingIntent.getStringExtra("clientMessageId")?.trim().orEmpty()

        if (from.isEmpty() || text.isEmpty()) return

        getSharedPreferences("zerolog_native_message", MODE_PRIVATE)
            .edit()
            .putString("from", from)
            .putString("to", to)
            .putString("text", text)
            .putString("id", id)
            .putString("clientMessageId", clientMessageId)
            .apply()
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        if (
            intent?.action == "zerolog.incoming_call" ||
            intent?.getBooleanExtra("zerolog_call", false) == true
        ) {
            applyIncomingCallLockScreen()
        }

        persistIncomingCallIntent(intent)
        persistMessageIntent(intent)

        if (
            intent?.action != "zerolog.incoming_call" &&
            intent?.getBooleanExtra("zerolog_call", false) != true
        ) {
            clearCallLockScreen()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val isIncomingCall =
            intent.action == "zerolog.incoming_call" ||
                intent.getBooleanExtra("zerolog_call", false)

        if (isIncomingCall) {
            applyIncomingCallLockScreen()
        }

        persistIncomingCallIntent(intent)
        persistMessageIntent(intent)

        if (isIncomingCall) {
            val from = intent.getStringExtra("from")?.trim().orEmpty()
            val to = intent.getStringExtra("to")?.trim().orEmpty()
            val callId = intent.getStringExtra("callId")?.trim().orEmpty()

            if (from.isNotEmpty() && to.isNotEmpty() && callId.isNotEmpty()) {
                try {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, channelName).invokeMethod(
                            "incomingCallIntent",
                            mapOf(
                                "type" to "callInvite",
                                "from" to from,
                                "to" to to,
                                "callId" to callId,
                            ),
                        )
                    }

                    android.util.Log.d(
                        "ZeroLogCall",
                        "Incoming call forwarded to Flutter: callId=$callId"
                    )
                } catch (e: Exception) {
                    android.util.Log.e(
                        "ZeroLogCall",
                        "Failed to forward incoming call to Flutter",
                        e
                    )
                }
            }
        }

        if (!isIncomingCall) {
            clearCallLockScreen()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIncomingCallIntent" -> {
                    // Cold start + notification tap + singleTop/onNewIntent
                    // durumlarının tamamında aynı pending-call kaynağını kullan.
                    persistIncomingCallIntent(intent)

                    val prefs =
                        getSharedPreferences("zerolog_native_call", MODE_PRIVATE)

                    val currentIntent = intent

                    val hasCallIntent =
                        currentIntent?.action == "zerolog.incoming_call" ||
                        currentIntent?.getBooleanExtra("zerolog_call", false) == true

                    val from = if (hasCallIntent) {
                        currentIntent?.getStringExtra("from")?.trim().orEmpty()
                    } else {
                        prefs.getString("from", "")?.trim().orEmpty()
                    }

                    val to = if (hasCallIntent) {
                        currentIntent?.getStringExtra("to")?.trim().orEmpty()
                    } else {
                        prefs.getString("to", "")?.trim().orEmpty()
                    }

                    val callId = if (hasCallIntent) {
                        currentIntent?.getStringExtra("callId")?.trim().orEmpty()
                    } else {
                        prefs.getString("callId", "")?.trim().orEmpty()
                    }

                    val data =
                        if (from.isNotEmpty() &&
                            to.isNotEmpty() &&
                            callId.isNotEmpty()
                        ) {
                            prefs.edit().clear().apply()

                            mapOf(
                                "type" to "callInvite",
                                "from" to from,
                                "to" to to,
                                "callId" to callId,
                            )
                        } else {
                            null
                        }

                    result.success(data)
                }
                "getPendingMessageIntent" -> {
                    val prefs =
                        getSharedPreferences("zerolog_native_message", MODE_PRIVATE)

                    val from = prefs.getString("from", "")?.trim().orEmpty()
                    val to = prefs.getString("to", "")?.trim().orEmpty()
                    val text = prefs.getString("text", "")?.trim().orEmpty()
                    val id = prefs.getString("id", "")?.trim().orEmpty()
                    val clientMessageId =
                        prefs.getString("clientMessageId", "")?.trim().orEmpty()

                    val data =
                        if (from.isNotEmpty() && text.isNotEmpty()) {
                            prefs.edit().clear().apply()

                            mapOf(
                                "type" to "privateMessage",
                                "from" to from,
                                "to" to to,
                                "text" to text,
                                "id" to id,
                                "clientMessageId" to clientMessageId,
                            )
                        } else {
                            null
                        }

                    result.success(data)
                }

                "requestStartupPermissions" -> {
                    requestStartupPermissions(result)
                }

                "requestFullScreenIntentPermission" -> {
                    requestFullScreenIntentPermission(result)
                }

                "requestCallPermissions" -> {
                    requestCallPermissions(result)
                }

                "startOutgoingCallTone" -> {
                    startOutgoingCallTone()
                    result.success(true)
                }

                "stopOutgoingCallTone" -> {
                    stopOutgoingCallTone()
                    result.success(true)
                }

                "stopIncomingCallTone" -> {
                    ZeroLogFirebaseMessagingService
                        .stopIncomingCallToneAndNotification(this)
                    result.success(true)
                }

                "clearCallLockScreen" -> {
                    clearCallLockScreen()
                    result.success(true)
                }

                "getDefaultRingtoneUri" -> {
                    try {
                        val uri: Uri? = RingtoneManager.getActualDefaultRingtoneUri(
                            this,
                            RingtoneManager.TYPE_RINGTONE
                        )

                        result.success(uri?.toString())
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopOutgoingCallTone()

        val incomingCallActive =
            intent?.action == "zerolog.incoming_call" ||
                intent?.getBooleanExtra("zerolog_call", false) == true

        if (!incomingCallActive) {
            clearCallLockScreen()
        }

        super.onDestroy()
    }

}
