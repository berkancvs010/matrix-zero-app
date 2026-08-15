package com.zerolog.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "zerolog/system"
    private val startupPermissionRequestCode = 7401
    private val callPermissionRequestCode = 7402
    private var outgoingCallPlayer: MediaPlayer? = null
    private var callPermissionResult:
        io.flutter.plugin.common.MethodChannel.Result? = null
    private var startupPermissionResult:
        io.flutter.plugin.common.MethodChannel.Result? = null

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
            outgoingCallPlayer = MediaPlayer.create(
                this,
                R.raw.zerolog_call
            )?.apply {
                isLooping = true
                setVolume(1.0f, 1.0f)
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

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        persistIncomingCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        persistIncomingCallIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIncomingCallIntent" -> {
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
                "requestStartupPermissions" -> {
                    requestStartupPermissions(result)
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
        clearCallLockScreen()
        super.onDestroy()
    }

}
