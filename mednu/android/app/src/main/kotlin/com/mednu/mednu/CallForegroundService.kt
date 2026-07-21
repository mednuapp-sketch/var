package com.mednu.mednu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the process alive during an active consultation
 * call. Without this service, Android kills the process when the user swipes
 * the app from recents, cutting off the Agora audio/video session.
 *
 * Start via [MainActivity] MethodChannel "mednu/active_call" → "startForeground".
 * Stop via the same channel "stopForeground", or the user can tap "End Call"
 * in the notification (broadcast caught by [MainActivity] and forwarded to Flutter).
 */
class CallForegroundService : Service() {

    companion object {
        const val CHANNEL_ID       = "mednu_active_call"
        const val NOTIFICATION_ID  = 9001
        const val ACTION_END_CALL  = "com.mednu.mednu.END_ACTIVE_CALL"
        const val EXTRA_CALLER_NAME = "callerName"
        const val EXTRA_CALL_ID    = "callId"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callerName = intent?.getStringExtra(EXTRA_CALLER_NAME) ?: ""
        val callId     = intent?.getStringExtra(EXTRA_CALL_ID) ?: ""
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification(callerName))
        return START_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Active Call",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "Ongoing MedNU consultation call"
                        setShowBadge(false)
                    }
                )
            }
        }
    }

    private fun buildNotification(callerName: String): Notification {
        // Tap notification → bring app to foreground (singleTop reuses the Activity)
        val openPi = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "End Call" action → broadcast → MainActivity → Flutter MethodChannel
        val endPi = PendingIntent.getBroadcast(
            this, 1,
            Intent(ACTION_END_CALL).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (callerName.isNotEmpty()) "In call with $callerName" else "MedNU Call Active"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText("Tap to return to call")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openPi)
            .addAction(android.R.drawable.ic_delete, "End Call", endPi)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
