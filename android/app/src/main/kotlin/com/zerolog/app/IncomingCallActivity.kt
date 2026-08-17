package com.zerolog.app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager

class IncomingCallActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        configureIncomingCallWindow()

        val incoming = Intent(this, MainActivity::class.java).apply {
            action = "zerolog.incoming_call"

            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP

            putExtra("zerolog_call", true)
            putExtra(
                "from",
                intent.getStringExtra("from").orEmpty()
            )
            putExtra(
                "to",
                intent.getStringExtra("to").orEmpty()
            )
            putExtra(
                "callId",
                intent.getStringExtra("callId").orEmpty()
            )
        }

        android.util.Log.d(
            "ZeroLogCall",
            "IncomingCallActivity launched: " +
                "from=${intent.getStringExtra("from")} " +
                "callId=${intent.getStringExtra("callId")}"
        )

        startActivity(incoming)
        finish()
    }

    private fun configureIncomingCallWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        android.util.Log.d(
            "ZeroLogCall",
            "IncomingCallActivity window configured"
        )
    }
}
