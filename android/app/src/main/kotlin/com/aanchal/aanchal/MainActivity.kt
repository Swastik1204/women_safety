package com.aanchal.aanchal

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector
import java.io.File
import java.io.FileOutputStream

/**
 * MainActivity with a stub MethodChannel for Nearby Connections.
 *
 * This is a placeholder — real Nearby Connections API calls will be
 * wired here once the native integration phase begins.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.aanchal/nearby"
        private const val ALARM_CHANNEL = "com.aanchal/alarm"
    }

    private val alarmHandler = Handler(Looper.getMainLooper())
    private var alarmPlayer: MediaPlayer? = null
    private var alarmStreamType: Int = AudioManager.STREAM_ALARM
    private var previousStreamVolume: Int? = null
    private var enforceRunnable: Runnable? = null
    private var rampRunnable: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDiscovery" -> {
                        // TODO: Wire Google Nearby Connections discovery
                        result.success("discovery_stub_ok")
                    }
                    "stopDiscovery" -> {
                        result.success("stop_stub_ok")
                    }
                    "broadcastSOS" -> {
                        val payload = call.argument<String>("payload") ?: ""
                        // TODO: Broadcast payload to discovered endpoints
                        result.success("broadcast_stub_ok: ${payload.take(40)}")
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            startAlarm(
                                asset = call.argument<String>("asset")
                                    ?: "assets/sounds/sound.mp3",
                                rampMs = call.argument<Int>("rampMs") ?: 3000,
                                enforceMax = call.argument<Boolean>("enforceMax") ?: true,
                                stream = call.argument<String>("stream") ?: "alarm",
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("alarm_start_failed", e.message, null)
                        }
                    }

                    "stop" -> {
                        val restore = call.argument<Boolean>("restoreVolume") ?: true
                        stopAlarm(restore)
                        result.success(true)
                    }

                    "isRunning" -> result.success(alarmPlayer != null)

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        stopAlarm(restoreVolume = true)
        super.onDestroy()
    }

    private fun startAlarm(
        asset: String,
        rampMs: Int,
        enforceMax: Boolean,
        stream: String,
    ) {
        if (alarmPlayer != null) return

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        alarmStreamType = if (stream == "music") AudioManager.STREAM_MUSIC else AudioManager.STREAM_ALARM
        previousStreamVolume = audioManager.getStreamVolume(alarmStreamType)
        val maxVolume = audioManager.getStreamMaxVolume(alarmStreamType)

        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)

        val mp = MediaPlayer()
        try {
            // Fast path (requires the asset to be stored uncompressed).
            val afd = assets.openFd(lookupKey)
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
        } catch (_: Exception) {
            // Fallback for compressed assets: copy to cache and play from file.
            val outFile = File(cacheDir, "alarm_sound.mp3")
            assets.open(lookupKey).use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            }
            mp.setDataSource(outFile.absolutePath)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
        } else {
            @Suppress("DEPRECATION")
            mp.setAudioStreamType(alarmStreamType)
        }

        mp.isLooping = true
        mp.setVolume(1.0f, 1.0f)
        mp.prepare()
        mp.start()
        alarmPlayer = mp

        // Ramp volume up to max.
        val currentVolume = audioManager.getStreamVolume(alarmStreamType)
        if (currentVolume < maxVolume) {
            val diff = maxVolume - currentVolume
            val stepIntervalMs = if (diff > 0) {
                (rampMs / diff).coerceIn(120, 800)
            } else {
                200
            }

            rampRunnable = object : Runnable {
                override fun run() {
                    val v = audioManager.getStreamVolume(alarmStreamType)
                    if (v >= maxVolume || alarmPlayer == null) return
                    audioManager.setStreamVolume(alarmStreamType, (v + 1).coerceAtMost(maxVolume), 0)
                    alarmHandler.postDelayed(this, stepIntervalMs.toLong())
                }
            }
            alarmHandler.post(rampRunnable!!)
        } else {
            audioManager.setStreamVolume(alarmStreamType, maxVolume, 0)
        }

        // Keep forcing volume back up while the alarm is running.
        if (enforceMax) {
            enforceRunnable = object : Runnable {
                override fun run() {
                    if (alarmPlayer == null) return
                    val v = audioManager.getStreamVolume(alarmStreamType)
                    if (v < maxVolume) {
                        audioManager.setStreamVolume(alarmStreamType, maxVolume, 0)
                    }
                    alarmHandler.postDelayed(this, 700)
                }
            }
            alarmHandler.post(enforceRunnable!!)
        }
    }

    private fun stopAlarm(restoreVolume: Boolean) {
        rampRunnable?.let { alarmHandler.removeCallbacks(it) }
        enforceRunnable?.let { alarmHandler.removeCallbacks(it) }
        rampRunnable = null
        enforceRunnable = null

        alarmPlayer?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        alarmPlayer = null

        if (restoreVolume) {
            val prev = previousStreamVolume
            if (prev != null) {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.setStreamVolume(alarmStreamType, prev, 0)
            }
        }
        previousStreamVolume = null
    }
}
