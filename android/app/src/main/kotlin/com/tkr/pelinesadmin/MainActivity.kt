package com.tkr.pelinesadmin

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alertPlayer: MediaPlayer? = null
    private var foreground = false
    private var pulseUntil = 0L
    private val patternHandler = Handler(Looper.getMainLooper())
    private val pattern by lazy {
        FiniteAlertPattern(
            schedule = { milliseconds, callback ->
                val task = Runnable { callback() }
                patternHandler.postDelayed(task, milliseconds)
                val cancel: () -> Unit = { patternHandler.removeCallbacks(task) }
                cancel
            },
            playSound = ::playDing,
            stopSound = ::releaseAudio,
        )
    }
    private val vibrator: Vibrator?
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun stopAlert() {
        pulseUntil = 0L
        pattern.stop()
        try { vibrator?.cancel() } catch (_: Exception) { }
    }

    private fun releaseAudio() {
        val player = alertPlayer
        alertPlayer = null
        player?.setOnCompletionListener(null)
        player?.setOnErrorListener(null)
        try { player?.release() } catch (_: Exception) { }
    }

    private fun soundAllowed(): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notifications = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return foreground && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                notifications.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL)
    }

    private fun playDing(completed: (Boolean) -> Unit) {
        if (!soundAllowed() || alertPlayer != null) {
            completed(false)
            return
        }
        try {
            val player = MediaPlayer()
            alertPlayer = player
            player.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            assets.openFd("flutter_assets/assets/sounds/new_order.wav").use {
                player.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            player.isLooping = false
            player.setOnCompletionListener {
                if (alertPlayer === it) {
                    releaseAudio()
                    completed(true)
                }
            }
            player.setOnErrorListener { failed, _, _ ->
                if (alertPlayer === failed) {
                    releaseAudio()
                    completed(false)
                }
                true
            }
            player.prepare()
            player.start()
        } catch (_: Exception) {
            releaseAudio()
            completed(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.pelines.admin/order_alert_sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "stop" -> { stopAlert(); result.success(null) }
                "play" -> {
                    if (!foreground || pattern.active || alertPlayer != null || SystemClock.elapsedRealtime() < pulseUntil) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val notifications = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    // Never bypass the user's interruption filter or raise volume.
                    val dnd = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                    if (dnd || audio.ringerMode == AudioManager.RINGER_MODE_SILENT) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val attributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                    pulseUntil = SystemClock.elapsedRealtime() + 550
                    // Haptics and audio fail independently. Each pulse is finite.
                    try {
                        vibrator?.takeIf { it.hasVibrator() }?.let {
                            val pattern = longArrayOf(0, 200, 150, 200)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                @Suppress("DEPRECATION")
                                it.vibrate(VibrationEffect.createWaveform(pattern, -1), attributes)
                            } else {
                                @Suppress("DEPRECATION")
                                it.vibrate(pattern, -1, attributes)
                            }
                        }
                    } catch (_: Exception) { }
                    if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                        pattern.start(call.argument<Int>("soundCount") ?: 1)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        foreground = true
    }

    override fun onPause() {
        foreground = false
        stopAlert()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopAlert()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        foreground = false
        stopAlert()
        super.onDestroy()
    }
}
