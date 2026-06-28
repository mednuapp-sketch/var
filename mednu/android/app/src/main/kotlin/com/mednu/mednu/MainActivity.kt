package com.mednu.mednu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity with two additions over the default FlutterFragmentActivity:
 *
 * 1. Flutter engine caching — while a call is active, the Flutter engine is
 *    stored in [FlutterEngineCache] so Android does not destroy the Dart VM
 *    when the user swipes the app from recents. The cached engine is reused
 *    when the Activity is recreated (e.g., the user taps the call notification).
 *
 * 2. "mednu/active_call" MethodChannel — lets Dart start/stop the
 *    [CallForegroundService] and receive the "End Call" notification action.
 */
class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "mednu/active_call"
    private var activeCallChannel: MethodChannel? = null

    companion object {
        private const val ENGINE_ID = "mednu_engine"

        // True while a call is active. Survives activity recreation as long as
        // the process lives (kept alive by the foreground service).
        @Volatile private var engineCached = false
    }

    // Use the cached engine when a call is active so the Dart VM (and Agora)
    // are not destroyed when the Activity is destroyed mid-call.
    override fun getCachedEngineId(): String? = if (engineCached) ENGINE_ID else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        activeCallChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        val callerName = call.argument<String>("callerName") ?: ""
                        val callId     = call.argument<String>("callId") ?: ""
                        // Cache engine first — prevents Dart VM death on swipe
                        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
                        engineCached = true
                        // Start foreground service — prevents process death on swipe
                        startCallService(callerName, callId)
                        result.success(null)
                    }
                    "stopForeground" -> {
                        stopService(Intent(this, CallForegroundService::class.java))
                        FlutterEngineCache.getInstance().remove(ENGINE_ID)
                        engineCached = false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        val filter = IntentFilter(CallForegroundService.ACTION_END_CALL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(endCallReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(endCallReceiver, filter)
        }
    }

    private fun startCallService(callerName: String, callId: String) {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            putExtra(CallForegroundService.EXTRA_CALLER_NAME, callerName)
            putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    // Forwards notification "End Call" taps to Dart via the MethodChannel.
    private val endCallReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            activeCallChannel?.invokeMethod("onEndCallFromNotification", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(endCallReceiver) } catch (_: Exception) {}
    }
}
