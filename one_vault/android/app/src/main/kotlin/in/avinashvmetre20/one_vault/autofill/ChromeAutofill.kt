package `in`.avinashvmetre20.one_vault.autofill

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri

object ChromeAutofill {
    private const val CHROME = "com.android.chrome"
    private const val PROVIDER = ".AutofillThirdPartyModeContentProvider"
    private const val COLUMN = "autofill_third_party_state"
    private const val PATH = "autofill_third_party_mode"

    fun isThirdPartyEnabled(context: Context): Boolean {
        return try {
            val uri = Uri.Builder()
                .scheme(ContentResolver.SCHEME_CONTENT)
                .authority(CHROME + PROVIDER)
                .path(PATH)
                .build()
            context.contentResolver.query(uri, arrayOf(COLUMN), null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return false
                val index = cursor.getColumnIndex(COLUMN)
                index != -1 && cursor.getInt(index) == 1
            } ?: false
        } catch (_: Exception) {
            false
        }
    }

    fun openSettings(context: Context) {
        val intent = Intent(Intent.ACTION_APPLICATION_PREFERENCES).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            addCategory(Intent.CATEGORY_APP_BROWSER)
            addCategory(Intent.CATEGORY_PREFERENCE)
            setPackage(CHROME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            context.startActivity(
                Intent.createChooser(intent, "Open Chrome Autofill settings")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}
