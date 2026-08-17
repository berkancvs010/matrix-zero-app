package com.zerolog.app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle

class IncomingCallActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )

        val incoming = Intent(this, MainActivity::class.java).apply {
            action = "zerolog.incoming_call"
            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP

            putExtra("zerolog_call", true)
            putExtra("from", intent.getStringExtra("from").orEmpty())
            putExtra("to", intent.getStringExtra("to").orEmpty())
            putExtra("callId", intent.getStringExtra("callId").orEmpty())
        }

        startActivity(incoming)
        finish()
    }
}
