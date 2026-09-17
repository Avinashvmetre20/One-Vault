package `in`.avinashvmetre20.one_vault.autofill

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object AutofillChannels {
    const val CHANNEL = "onevault/autofill"

    fun register(activity: FlutterFragmentActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pendingSaves" -> result.success(
                    AutofillStore.pending(activity).map { it.toMap() },
                )
                "syncCredentials" -> {
                    val raw = call.arguments as? List<*> ?: emptyList<Any>()
                    val items = raw.mapNotNull { entry ->
                        val map = entry as? Map<*, *> ?: return@mapNotNull null
                        val id = map["id"] as? String ?: return@mapNotNull null
                        StoredLogin(
                            id = id,
                            title = map["title"] as? String ?: "",
                            username = map["username"] as? String ?: "",
                            password = map["password"] as? String ?: "",
                            domain = map["domain"] as? String ?: "",
                            website = map["website"] as? String ?: "",
                        )
                    }
                    AutofillStore.syncFromVault(activity, items)
                    result.success(null)
                }
                "clearCredentials" -> {
                    AutofillStore.clear(activity)
                    result.success(null)
                }
                "isEnabled" -> result.success(isEnabled(activity))
                "openSettings" -> {
                    openSettings(activity)
                    result.success(null)
                }
                "isChromeThirdParty" -> result.success(ChromeAutofill.isThirdPartyEnabled(activity))
                "openChromeSettings" -> {
                    ChromeAutofill.openSettings(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isEnabled(activity: FlutterFragmentActivity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = activity.getSystemService(AutofillManager::class.java) ?: return false
        if (!manager.isAutofillSupported) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val enabled = manager.autofillServiceComponentName ?: return false
            return enabled.packageName == activity.packageName
        }
        return manager.hasEnabledAutofillServices()
    }

    private fun openSettings(activity: FlutterFragmentActivity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            activity.startActivity(intent)
        } else {
            activity.startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }
}
