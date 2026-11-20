package com.smartfeeder.smart_chicken_feeder

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "smart_chicken_feeder/sound"
    private var activePlayer: MediaPlayer? = null
    private var lastPlayedAtMs: Long = 0L
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "playChickenCluck") {
                    playChickenCluckOneSecond()
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun playChickenCluckOneSecond() {
        val now = System.currentTimeMillis()
        if (now - lastPlayedAtMs < 900L) return
        lastPlayedAtMs = now

        try {
            activePlayer?.let {
                try {
                    if (it.isPlaying) it.stop()
                } catch (_: Exception) {}
                it.release()
            }
            activePlayer = null

            val mp = MediaPlayer.create(applicationContext, R.raw.chicken_cluck) ?: return
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            activePlayer = mp
            mp.setOnCompletionListener { player ->
                player.release()
                if (activePlayer === player) activePlayer = null
            }
            mp.start()

            // Hard 1.0-second stop cap so sound never plays longer than 1 second
            mainHandler.postDelayed({
                if (activePlayer === mp) {
                    try {
                        if (mp.isPlaying) mp.stop()
                    } catch (_: Exception) {}
                    mp.release()
                    activePlayer = null
                }
            }, 1000L)
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        activePlayer?.release()
        activePlayer = null
        super.onDestroy()
    }
}
