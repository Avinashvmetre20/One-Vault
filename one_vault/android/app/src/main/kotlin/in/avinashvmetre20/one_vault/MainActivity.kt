package `in`.avinashvmetre20.one_vault

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import `in`.avinashvmetre20.one_vault.autofill.AutofillChannels
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var secureRequested = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun onPause() {
        if (secureRequested) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        // FLAG_SECURE while typing leaves a white gap above the keyboard.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        applyRecentsSecure()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "onevault/screen_security"
        ).setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                secureRequested = call.arguments as? Boolean ?: false
                applyRecentsSecure()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        AutofillChannels.register(this, flutterEngine)
    }

    private fun applyRecentsSecure() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(!secureRequested)
        }
    }
}
