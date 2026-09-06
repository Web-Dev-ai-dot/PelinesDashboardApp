package com.example.pelines_admin_app

import android.media.AudioAttributes
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alertPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pelines.admin/order_alert_sound",
        ).setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (alertPlayer?.isPlaying == true) {
                result.success(null)
                return@setMethodCallHandler
            }
            try {
                val descriptor = assets.openFd(
                    "flutter_assets/assets/sounds/new_order.wav",
                )
                alertPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(
                        descriptor.fileDescriptor,
                        descriptor.startOffset,
                        descriptor.length,
                    )
                    descriptor.close()
                    setOnCompletionListener { player ->
                        player.release()
                        if (alertPlayer === player) alertPlayer = null
                    }
                    setOnErrorListener { player, _, _ ->
                        player.release()
                        if (alertPlayer === player) alertPlayer = null
                        true
                    }
                    prepare()
                    start()
                }
                result.success(null)
            } catch (error: Exception) {
                alertPlayer?.release()
                alertPlayer = null
                result.error("audio_error", error.message, null)
            }
        }
    }

    override fun onDestroy() {
        alertPlayer?.release()
        alertPlayer = null
        super.onDestroy()
    }
}
