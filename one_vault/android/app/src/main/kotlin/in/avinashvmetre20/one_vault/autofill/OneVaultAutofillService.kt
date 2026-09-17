package `in`.avinashvmetre20.one_vault.autofill

import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.O)
class OneVaultAutofillService : AutofillService() {
    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val clientPackage = structure.activityComponent?.packageName ?: packageName
        val parsed = AutofillParser.parse(structure, clientPackage)
        if (!parsed.canFill) {
            callback.onSuccess(null)
            return
        }

        val builder = FillResponse.Builder()
        for (item in AutofillStore.match(this, parsed.domain).take(5)) {
            val label = item.username.ifEmpty { item.title }
            val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
                setTextViewText(android.R.id.text1, label)
            }
            val dataset = Dataset.Builder()
            parsed.usernameId?.let {
                dataset.setValue(it, AutofillValue.forText(item.username), presentation)
            }
            parsed.passwordId?.let {
                dataset.setValue(it, AutofillValue.forText(item.password), presentation)
            }
            builder.addDataset(dataset.build())
        }

        val saveIds = listOfNotNull(parsed.usernameId, parsed.passwordId).toTypedArray()
        if (saveIds.isNotEmpty()) {
            var saveType = SaveInfo.SAVE_DATA_TYPE_PASSWORD
            if (parsed.usernameId != null) saveType = saveType or SaveInfo.SAVE_DATA_TYPE_USERNAME
            builder.setSaveInfo(
                SaveInfo.Builder(saveType, saveIds)
                    .setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
                    .build(),
            )
        }
        callback.onSuccess(builder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        var username = ""
        var password = ""
        var domain = ""

        for (context in request.fillContexts) {
            val structure = context.structure
            val parsed = AutofillParser.parse(
                structure,
                structure.activityComponent?.packageName ?: packageName,
            )
            if (parsed.usernameValue.isNotEmpty()) username = parsed.usernameValue
            if (parsed.passwordValue.isNotEmpty()) password = parsed.passwordValue
            if (parsed.domain.isNotEmpty()) domain = parsed.domain
        }

        if (password.isNotEmpty()) {
            AutofillStore.saveLogin(this, username, password, domain)
        }
        callback.onSuccess()
    }
}
