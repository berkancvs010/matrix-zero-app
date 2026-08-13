package com.zerolog.app

import android.Manifest
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "zerolog/system"
    private val startupPermissionRequestCode = 7401
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

        if (
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.RECORD_AUDIO)
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStartupPermissions" -> {
                    requestStartupPermissions(result)
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
}
