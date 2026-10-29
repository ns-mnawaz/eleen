package com.eleen.eleen

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "eleen/session_fg",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        SessionForegroundService.start(applicationContext)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("fgs_error", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        SessionForegroundService.stop(applicationContext)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("fgs_error", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Brings Eleen to the front over whatever app is running (YouTube,
        // Netflix) so the in-app lock covers the TV with working remote
        // input, and the running app's activity is paused (playback stops).
        // Only ever called from the background (Eleen holds
        // SYSTEM_ALERT_WINDOW, which exempts it from the background-activity
        // start restrictions). A SYSTEM_ALERT_WINDOW overlay cannot take
        // remote key input on this platform, so the interactive lock lives
        // in the real activity, not the overlay.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "eleen/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToFront" -> {
                    try {
                        val intent = Intent(applicationContext, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("front_error", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
