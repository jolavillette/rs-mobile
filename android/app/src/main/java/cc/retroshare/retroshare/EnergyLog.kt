package cc.retroshare.retroshare

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Process
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

// What the Energy page shows comes from here. The service process, which
// runs the core, appends one line of counters to a file at each keep-alive,
// each time the phone starts or stops sleeping between keep-alives, and when
// the page asks; the page reads the file and compares lines. Nothing here
// wakes the phone: every sample is taken while it is already awake.
object EnergyLog {
    const val ACTION_SAMPLE = "cc.retroshare.retroshare.ENERGY_SAMPLE"
    private const val CHANNEL_NAME = "cc.retroshare.retroshare/energy"
    private const val FILE_NAME = "energy-log.csv"
    private const val KEEP_MS = 8L * 24 * 3600 * 1000
    private const val DUMPSYS_TIMEOUT_SECONDS = 20L

    // One sample at a time, off the caller's thread: reading the system's
    // battery statistics takes seconds.
    private val worker = Executors.newSingleThreadExecutor()

    // Counters of the service process, since it started.
    private var keepAlives = 0L
    private var incomingWakes = 0L
    private var heldAwakeMs = 0L

    // When the permanent wake lock was taken, on the elapsedRealtime clock;
    // 0 while it is released.
    private var permanentSince = 0L

    private fun logFile(context: Context) = File(context.filesDir, FILE_NAME)

    // Service process: the service starts, holding its permanent wake lock.
    fun serviceStarted(context: Context) {
        val app = context.applicationContext
        synchronized(this) { permanentSince = SystemClock.elapsedRealtime() }
        worker.execute {
            trim(app)
            write(app, quiet = false, withAppPower = true)
        }
    }

    // Service process: the phone starts (allowed) or stops sleeping between
    // its keep-alives. The line written carries the state that begins.
    fun sleepAllowedChanged(context: Context, allowed: Boolean) {
        val app = context.applicationContext
        synchronized(this) {
            val now = SystemClock.elapsedRealtime()
            if (allowed && permanentSince != 0L) {
                heldAwakeMs += now - permanentSince
                permanentSince = 0L
            } else if (!allowed && permanentSince == 0L) {
                permanentSince = now
            }
        }
        worker.execute { write(app, quiet = allowed, withAppPower = true) }
    }

    // Service process: a keep-alive alarm was handled.
    fun keepAlive(context: Context, quiet: Boolean) {
        val app = context.applicationContext
        synchronized(this) { keepAlives++ }
        worker.execute { write(app, quiet, withAppPower = false) }
    }

    // Service process: an arrived item woke the phone.
    fun incomingWake() {
        synchronized(this) { incomingWakes++ }
    }

    // Service process: the short wake lock was extended by this long.
    fun shortLock(ms: Long) {
        synchronized(this) { if (permanentSince == 0L && ms > 0) heldAwakeMs += ms }
    }

    // Service process: the page asks for a fresh line.
    fun sampleNow(context: Context, quiet: Boolean) {
        val app = context.applicationContext
        worker.execute { write(app, quiet, withAppPower = true) }
    }

    private fun write(context: Context, quiet: Boolean, withAppPower: Boolean) {
        try {
            val now = SystemClock.elapsedRealtime()
            val held: Long
            val alarms: Long
            val incoming: Long
            synchronized(this) {
                held = heldAwakeMs + if (permanentSince != 0L) now - permanentSince else 0L
                alarms = keepAlives
                incoming = incomingWakes
            }
            val uid = Process.myUid()
            val battery = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val status = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val plugged = (status?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
            val line = listOf(
                System.currentTimeMillis(),
                now,
                SystemClock.uptimeMillis(),
                Process.myPid(),
                Process.getElapsedCpuTime(),
                TrafficStats.getUidRxBytes(uid),
                TrafficStats.getUidTxBytes(uid),
                TrafficStats.getUidRxPackets(uid),
                TrafficStats.getUidTxPackets(uid),
                network(context),
                battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER),
                if (plugged) 1 else 0,
                if (quiet) 1 else 0,
                held,
                alarms,
                incoming,
                if (withAppPower) appPowerMah(context) else -1.0,
            ).joinToString(";")
            logFile(context).appendText(line + "\n")
        } catch (_: Exception) {
            // A missing line only shortens what the page can show.
        }
    }

    // "w" on Wi-Fi, "m" on a mobile network, "n" with no network.
    private fun network(context: Context): String {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return "n"
        return if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) "m" else "w"
    }

    // Both permissions are of the kind only adb can grant.
    fun hasPowerPermissions(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.BATTERY_STATS) ==
            PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.DUMP) ==
            PackageManager.PERMISSION_GRANTED

    // What Android's battery statistics charge to this application since
    // they were last reset, in mAh; -1 when the permissions are missing or
    // the figure cannot be read.
    private fun appPowerMah(context: Context): Double {
        if (!hasPowerPermissions(context)) return -1.0
        var process: java.lang.Process? = null
        try {
            process = ProcessBuilder("dumpsys", "batterystats")
                .redirectErrorStream(true)
                .start()
            val running = process
            val guard = Thread {
                if (!running.waitFor(DUMPSYS_TIMEOUT_SECONDS, TimeUnit.SECONDS)) running.destroy()
            }.apply { start() }
            val appId = Process.myUid() % 100000 - Process.FIRST_APPLICATION_UID
            val wanted = Regex("^\\s*UID u\\d+a$appId: ([0-9.]+)")
            var found = -1.0
            running.inputStream.bufferedReader().useLines { lines ->
                for (text in lines) {
                    val match = wanted.find(text) ?: continue
                    found = match.groupValues[1].toDoubleOrNull() ?: -1.0
                    break
                }
            }
            running.destroy()
            guard.interrupt()
            return found
        } catch (_: Exception) {
            process?.destroy()
            return -1.0
        }
    }

    // Drops the lines older than the longest period the page shows.
    private fun trim(context: Context) {
        try {
            val file = logFile(context)
            if (!file.exists()) return
            val oldest = System.currentTimeMillis() - KEEP_MS
            val kept = file.readLines().filter {
                (it.substringBefore(';').toLongOrNull() ?: 0L) >= oldest
            }
            file.writeText(if (kept.isEmpty()) "" else kept.joinToString("\n") + "\n")
        } catch (_: Exception) {
        }
    }

    // Interface process: what the Energy page calls.
    fun registerChannel(flutterEngine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sample" -> {
                        // Asking a stopped service would start it without a core.
                        if (!RetroShareServiceAndroid.isRunning(app)) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            app.startService(
                                Intent(app, RetroShareServiceAndroid::class.java)
                                    .setAction(ACTION_SAMPLE),
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "log" -> {
                        val file = logFile(app)
                        result.success(if (file.exists()) file.readText() else "")
                    }
                    "powerPermissions" -> result.success(hasPowerPermissions(app))
                    "packageName" -> result.success(app.packageName)
                    else -> result.notImplemented()
                }
            }
    }
}
