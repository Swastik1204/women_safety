package my.aanchal

import android.content.Context
import android.content.pm.PackageManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
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
        private const val SMS_CHANNEL = "com.aanchal/sms"
        private const val AUDIO_CHANNEL = "com.aanchal.app/audio"
        private const val SIM_CHANNEL = "com.aanchal.app/sim"
        private const val SOS_CHANNEL_ID = "aanchal_sos"
        private const val REQUEST_PHONE_CODE = 1002
    }

    private val alarmHandler = Handler(Looper.getMainLooper())
    private var alarmPlayer: MediaPlayer? = null
    private var alarmStreamType: Int = AudioManager.STREAM_ALARM
    private var previousStreamVolume: Int? = null
    private var enforceRunnable: Runnable? = null
    private var rampRunnable: Runnable? = null
    private var pendingPhonePermissionResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        if (phone.isEmpty() || message.isEmpty()) {
                            result.error("invalid_args", "phone and message required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            @Suppress("DEPRECATION")
                            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                getSystemService(SmsManager::class.java)
                            } else {
                                SmsManager.getDefault()
                            }
                            val parts = smsManager.divideMessage(message)
                            if (parts.size > 1) {
                                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                            } else {
                                smsManager.sendTextMessage(phone, null, message, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("sms_failed", e.message, null)
                        }
                    }

                    "sendSmsBatch" -> {
                        val phones = call.argument<List<String>>("phones") ?: emptyList()
                        val message = call.argument<String>("message") ?: ""

                        if (phones.isEmpty() || message.isEmpty()) {
                            result.error("invalid_args", "phones and message required", null)
                            return@setMethodCallHandler
                        }

                        var sent = 0
                        val failed = mutableListOf<String>()
                        try {
                            @Suppress("DEPRECATION")
                            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                getSystemService(SmsManager::class.java)
                            } else {
                                SmsManager.getDefault()
                            }

                            for (phone in phones) {
                                try {
                                    val parts = smsManager.divideMessage(message)
                                    if (parts.size > 1) {
                                        smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                                    } else {
                                        smsManager.sendTextMessage(phone, null, message, null, null)
                                    }
                                    sent += 1
                                } catch (e: Exception) {
                                    failed.add(phone)
                                }
                            }

                            result.success(
                                mapOf(
                                    "sent" to sent,
                                    "failed" to failed,
                                )
                            )
                        } catch (e: Exception) {
                            result.error("sms_batch_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlarmStream" -> {
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

                            // Set alarm stream to maximum volume
                            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_ALARM,
                                maxVol,
                                0,
                            )

                            // Override DND only if permission is already granted
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            if (nm.isNotificationPolicyAccessGranted) {
                                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
                            }

                            result.success("ok")
                        } catch (e: Exception) {
                            result.error("audio_stream_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSimNumbers" -> {
                        try {
                            result.success(getSimNumbers())
                        } catch (e: Exception) {
                            result.error("sim_read_failed", e.message, null)
                        }
                    }

                    "requestPhonePermission" -> {
                        if (hasPhoneReadPermission()) {
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        pendingPhonePermissionResult?.success(false)
                        pendingPhonePermissionResult = result

                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                android.Manifest.permission.READ_PHONE_NUMBERS,
                                android.Manifest.permission.READ_PHONE_STATE,
                            ),
                            REQUEST_PHONE_CODE,
                        )
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == REQUEST_PHONE_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingPhonePermissionResult?.success(granted)
            pendingPhonePermissionResult = null
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
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

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(SOS_CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            SOS_CHANNEL_ID,
            "Aanchal SOS Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Emergency SOS alerts"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun hasPhoneReadPermission(): Boolean {
        val readPhoneNumbersGranted =
            checkSelfPermission(android.Manifest.permission.READ_PHONE_NUMBERS) ==
                PackageManager.PERMISSION_GRANTED
        val readPhoneStateGranted =
            checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) ==
                PackageManager.PERMISSION_GRANTED
        return readPhoneNumbersGranted || readPhoneStateGranted
    }

    private fun normalizePhoneNumber(raw: String?): String {
        val cleaned = raw
            ?.replace(" ", "")
            ?.replace("-", "")
            ?.replace("(", "")
            ?.replace(")", "")
            ?.trim()
            ?: ""

        return if (
            cleaned.length == 10 &&
            cleaned.matches(Regex("^[6-9]\\d{9}$"))
        ) {
            "+91$cleaned"
        } else {
            cleaned
        }
    }

    private fun getSimNumbers(): List<Map<String, String>> {
        val sims = mutableListOf<Map<String, String>>()

        if (hasPhoneReadPermission()) {
            val subManager =
                getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val subscriptions = subManager.activeSubscriptionInfoList ?: emptyList()

            for (sub in subscriptions) {
                val number = normalizePhoneNumber(sub.number)
                val displayName = sub.displayName
                    ?.toString()
                    ?.takeIf { it.isNotBlank() }
                    ?: "SIM ${sub.simSlotIndex + 1}"

                sims.add(
                    mapOf(
                        "slotIndex" to sub.simSlotIndex.toString(),
                        "displayName" to displayName,
                        "phoneNumber" to number,
                    )
                )
            }
        }

        if (sims.isEmpty() && hasPhoneReadPermission()) {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val number = normalizePhoneNumber(tm.line1Number)
            sims.add(
                mapOf(
                    "slotIndex" to "0",
                    "displayName" to "SIM 1",
                    "phoneNumber" to number,
                )
            )
        }

        return sims
    }
}
