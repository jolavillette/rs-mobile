package cc.retroshare.retroshare

import android.annotation.SuppressLint
import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.system.exitProcess
import org.retroshare.service.RetroShareServiceAndroid as RsService

class RetroShareServiceAndroid : RsService() {

    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val ACTION_SHUTDOWN = "SHUTDOWN"
        const val CHANNEL_ID = "cc.retroshare.retroshare/retroshare"
        private const val WAKELOCK_TAG = "RetroShareServiceAndroid:Wakelock"

        // MobileLink keep-alive while the phone sleeps.
        private const val ACTION_KEEP_ALIVE = "cc.retroshare.retroshare.MOBILE_LINK_KEEP_ALIVE"
        private const val DEFAULT_KEEP_ALIVE_SECONDS = 240
        private const val KEEP_ALIVE_TIMEOUT_SECONDS = 10
        private const val KEEP_ALIVE_WAKE_MS = 15_000L
        private const val INCOMING_WAKE_MS = 5_000L

        private val JSON_API_PORT_KEY = RsService::class.java.canonicalName + "/JSON_API_PORT_KEY"
        private val JSON_API_BIND_ADDRESS_KEY =
            RsService::class.java.canonicalName + "/JSON_API_BIND_ADDRESS_KEY"

        private var rsInitialized = false

        fun start(
            ctx: Context,
            jsonApiPort: Int = DEFAULT_JSON_API_PORT,
            jsonApiBindAddress: String = DEFAULT_JSON_API_BINDING_ADDRESS,
        ) {
            val intent = Intent(ctx, RetroShareServiceAndroid::class.java)
            intent.putExtra(JSON_API_PORT_KEY, jsonApiPort)
            intent.putExtra(JSON_API_BIND_ADDRESS_KEY, jsonApiBindAddress)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        }

        fun stop(ctx: Context) {
            val intent = Intent(ctx, RetroShareServiceAndroid::class.java)
            ctx.stopService(intent)
        }

        fun isRunning(ctx: Context): Boolean {
            val manager = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (service in manager.getRunningServices(Int.MAX_VALUE)) {
                if (RetroShareServiceAndroid::class.java.name == service.service.className) {
                    return true
                }
            }
            return false
        }
    }

    @SuppressLint("WakelockTimeout")
    override fun onCreate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "RetroShare Service Channel",
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RetroShare")
            .setContentText("RetroShare works in the background.")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .build()

        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)
            .apply {
                setReferenceCounted(false)
                acquire()
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                1,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(1, notification)
        }

        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SHUTDOWN) {
            @Suppress("DEPRECATION")
            stopForeground(true)
            stopSelf()
        } else if (!rsInitialized) {
            rsInitialized = true
            super.onStartCommand(intent, flags, startId)
        }
        // Android 12+ may not recreate a foreground service while the app is in
        // the background. Let the visible activity explicitly start it instead.
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Defensive fallback for Android foreground-service limits. A service
        // must stop promptly after this callback or Android crashes its process.
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf(startId)
    }

    override fun onDestroy() {
        rsInitialized = false
        cancelKeepAlive()
        if (keepAliveReceiverRegistered) {
            unregisterReceiver(keepAliveReceiver)
            keepAliveReceiverRegistered = false
        }
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()

        // libretroshare keeps process-wide native singletons (including
        // AuthSSL) after the Android Service is destroyed. This service runs
        // in its own :retroshare process so terminating that now-empty process
        // is required to unlock a different location safely.
        if (android.app.Application.getProcessName().endsWith(":retroshare")) {
            exitProcess(0)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    // MobileLink: while the phone is in background with a home that spares
    // it, libretroshare allows it to sleep. The service then drops its wake
    // lock, and an alarm wakes the phone every keep-alive interval to tell
    // the home it is still there. An item that arrives wakes the phone by
    // itself; the service keeps it awake a few seconds to handle it.

    @Volatile
    private var sleepAllowed = false

    private val shortWakeLock: PowerManager.WakeLock by lazy {
        (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$WAKELOCK_TAG:short")
            .apply { setReferenceCounted(false) }
    }

    private var keepAliveReceiverRegistered = false

    private val keepAliveReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val pending = goAsync()
            shortWakeLock.acquire(KEEP_ALIVE_WAKE_MS)
            // The keep-alive waits for the home's answer: off the main thread.
            Thread {
                try {
                    RsService.nativeMobileLinkKeepAlive(KEEP_ALIVE_TIMEOUT_SECONDS)
                    if (sleepAllowed) scheduleKeepAlive()
                } finally {
                    pending.finish()
                }
            }.start()
        }
    }

    @SuppressLint("WakelockTimeout")
    override fun onMobileLinkSleepAllowed(allowed: Boolean) {
        sleepAllowed = allowed
        if (allowed) {
            if (!keepAliveReceiverRegistered) {
                ContextCompat.registerReceiver(
                    this,
                    keepAliveReceiver,
                    IntentFilter(ACTION_KEEP_ALIVE),
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                keepAliveReceiverRegistered = true
            }
            scheduleKeepAlive()
            wakeLock?.let { if (it.isHeld) it.release() }
        } else {
            cancelKeepAlive()
            wakeLock?.acquire()
        }
    }

    override fun onMobileLinkWakeUp() {
        shortWakeLock.acquire(INCOMING_WAKE_MS)
    }

    private fun keepAliveIntent(): PendingIntent = PendingIntent.getBroadcast(
        this,
        0,
        Intent(ACTION_KEEP_ALIVE).setPackage(packageName),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun scheduleKeepAlive() {
        val seconds = RsService.nativeMobileLinkKeepAliveInterval()
            .takeIf { it > 0 } ?: DEFAULT_KEEP_ALIVE_SECONDS
        val at = SystemClock.elapsedRealtime() + seconds * 1000L
        val alarms = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // An exact alarm needs the user's grant from Android 12 on; without
        // it Android may delay the alarm a little, which the home tolerates.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarms.canScheduleExactAlarms()) {
            alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, keepAliveIntent())
        } else {
            alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, keepAliveIntent())
        }
    }

    private fun cancelKeepAlive() {
        (getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(keepAliveIntent())
    }

}
