package com.smartblealarm.smart_ble_alarm

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Telephony
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Hosts the Flutter engine and backs the `wakeguard/alarm` MethodChannel that
/// the Dart [AndroidAlarmChannel] drives: the offline system-alarm sound, the
/// lock-screen/keep-awake flags for the full-screen alarm, and the Phone/
/// Messages shortcuts. Every native action is wrapped so a failure degrades to
/// "the visual alarm + haptics still ring" rather than crashing the app.
class MainActivity : FlutterActivity() {
    private val channelName = "wakeguard/alarm"
    private var alarmPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Let a full-screen-intent launch appear over the lock screen and turn
        // the display on. Harmless when the app is opened normally — it only
        // matters when this activity is brought to the front over the keyguard.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playSystemAlarm" -> {
                        startAlarmSound()
                        result.success(true)
                    }
                    "stopSystemAlarm" -> {
                        stopAlarmSound()
                        result.success(true)
                    }
                    "armLockScreen" -> {
                        armLockScreen()
                        result.success(true)
                    }
                    "disarmLockScreen" -> {
                        disarmLockScreen()
                        result.success(true)
                    }
                    "openDialer" -> {
                        openDialer()
                        result.success(true)
                    }
                    "openMessages" -> {
                        openMessages()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Loop the user's system-selected alarm sound on the alarm audio stream.
    /// Falls back through ringtone -> default alarm so it always makes noise.
    private fun startAlarmSound() {
        try {
            stopAlarmSound()
            val uri: Uri =
                RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val player = MediaPlayer()
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.setDataSource(this, uri)
            player.isLooping = true
            player.prepare()
            player.start()
            alarmPlayer = player
        } catch (e: Exception) {
            // Best-effort: the visual alarm + haptics carry the ring.
            stopAlarmSound()
        }
    }

    private fun stopAlarmSound() {
        try {
            alarmPlayer?.stop()
        } catch (_: Exception) {
        }
        try {
            alarmPlayer?.release()
        } catch (_: Exception) {
        }
        alarmPlayer = null
    }

    private fun armLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                km?.requestDismissKeyguard(this, null)
            }
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } catch (_: Exception) {
        }
    }

    private fun disarmLockScreen() {
        try {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } catch (_: Exception) {
        }
    }

    private fun openDialer() {
        try {
            startActivity(
                Intent(Intent.ACTION_DIAL).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }

    private fun openMessages() {
        try {
            val defaultSms = Telephony.Sms.getDefaultSmsPackage(this)
            val intent =
                if (defaultSms != null) {
                    packageManager.getLaunchIntentForPackage(defaultSms)
                } else {
                    Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_MESSAGING)
                }
            intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent != null) startActivity(intent)
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        stopAlarmSound()
        super.onDestroy()
    }
}
