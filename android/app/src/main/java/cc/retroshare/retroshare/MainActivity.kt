package cc.retroshare.retroshare

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewTreeObserver
import android.view.WindowInsets
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL_NAME = "cc.retroshare.retroshare/retroshare"
    private var activityResumed = false

    // Flutter holds the keyboard insets back while the keyboard animates and
    // hands them to its view when the animation ends. When that end does not
    // come, Flutter keeps the keyboard's height after the keyboard is gone and
    // every screen stops that far above the bottom of the display. So, once
    // Android reports the keyboard hidden, the Flutter view gets the window's
    // insets again. From Android 15 on, the app draws edge to edge: the
    // Flutter view receives the window's insets unchanged, so handing them
    // over again changes nothing when Flutter was right.
    private var keyboardShown = false
    private val keyboardResync = Runnable { resyncKeyboardInsets() }
    private val keyboardWatch = ViewTreeObserver.OnGlobalLayoutListener {
        val shown = keyboardVisible() ?: return@OnGlobalLayoutListener
        if (keyboardShown && !shown) scheduleKeyboardResync()
        keyboardShown = shown
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            window.decorView.viewTreeObserver.addOnGlobalLayoutListener(keyboardWatch)
        }
    }

    override fun onDestroy() {
        window.decorView.removeCallbacks(keyboardResync)
        window.decorView.viewTreeObserver.removeOnGlobalLayoutListener(keyboardWatch)
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) scheduleKeyboardResync()
    }

    /** True or false from Android 15 on, null before. */
    private fun keyboardVisible(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return null
        val insets = window.decorView.rootWindowInsets ?: return null
        return insets.isVisible(WindowInsets.Type.ime())
    }

    // After the keyboard's own hide animation, which lasts about 300 ms.
    private fun scheduleKeyboardResync() {
        val decor = window.decorView
        decor.removeCallbacks(keyboardResync)
        decor.postDelayed(keyboardResync, 600)
    }

    private fun resyncKeyboardInsets() {
        if (keyboardVisible() != false) return
        val insets = window.decorView.rootWindowInsets ?: return
        val flutterView = findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID) ?: return
        flutterView.onApplyWindowInsets(WindowInsets(insets))
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        // Recover a backend that Android stopped while the UI process remained
        // cached. Foreground-service starts are allowed while this activity is
        // visible.
        if (!RetroShareServiceAndroid.isRunning(applicationContext)) {
            try {
                RetroShareServiceAndroid.start(applicationContext)
            } catch (_: Exception) {
                // Flutter's startup flow reports and retries visible failures.
            }
        }
    }

    override fun onPause() {
        activityResumed = false
        super.onPause()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (!activityResumed) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        RetroShareServiceAndroid.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    RetroShareServiceAndroid.stop(applicationContext)
                    result.success(true)
                }
                // The port this application's core listens on.
                "jsonApiPort" -> result.success(CorePort.JSON_API)
                "restart" -> {
                    try {
                        RetroShareServiceAndroid.stop(applicationContext)
                        RetroShareServiceAndroid.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RESTART_FAILED", e.message, null)
                    }
                }
                "isRunning" -> {
                    result.success(RetroShareServiceAndroid.isRunning(applicationContext))
                }
                else -> result.notImplemented()
            }
        }
    }

}
