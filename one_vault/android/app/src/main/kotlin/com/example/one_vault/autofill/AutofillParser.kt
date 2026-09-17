package com.example.one_vault.autofill

import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.app.assist.AssistStructure
import android.app.assist.AssistStructure.ViewNode

data class AutofillFields(
    val usernameId: AutofillId?,
    val passwordId: AutofillId?,
    val usernameValue: String,
    val passwordValue: String,
    val domain: String,
    val packageName: String,
    val fillIds: Array<AutofillId>,
) {
    val canFill: Boolean get() = fillIds.isNotEmpty() && (usernameId != null || passwordId != null)
}

object AutofillParser {
    fun parse(structure: AssistStructure, fallbackPackage: String): AutofillFields {
        var usernameId: AutofillId? = null
        var passwordId: AutofillId? = null
        var usernameValue = ""
        var passwordValue = ""
        var domain = ""
        val ids = mutableListOf<AutofillId>()
        val textFields = mutableListOf<Pair<AutofillId, String>>()

        for (i in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(i).rootViewNode) { node ->
                val web = node.webDomain.orEmpty()
                if (web.isNotBlank() && domain.isEmpty()) domain = web

                val id = node.autofillId ?: return@walk
                val hints = node.autofillHints?.map { it.lowercase() } ?: emptyList()
                val html = node.htmlInfo
                val attrs = html?.attributes ?: emptyList()
                fun attr(name: String) = attrs.firstOrNull { it.first.equals(name, true) }?.second.orEmpty()
                val htmlType = attr("type").lowercase()
                val htmlAuto = attr("autocomplete").lowercase()
                val htmlName = "${attr("name")} ${attr("id")} $htmlAuto".lowercase()
                val tag = html?.tag?.lowercase().orEmpty()
                val variation = node.inputType and InputType.TYPE_MASK_VARIATION
                val isPassword = hints.any { it.contains("password") } ||
                    htmlType == "password" ||
                    htmlAuto.contains("password") ||
                    htmlName.contains("password") ||
                    variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                    variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                    variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                val isUsername = !isPassword && (
                    hints.any {
                        it.contains("username") ||
                            it.contains("email") ||
                            it == View.AUTOFILL_HINT_USERNAME ||
                            it == View.AUTOFILL_HINT_EMAIL_ADDRESS
                    } ||
                    htmlType == "email" ||
                    htmlAuto.contains("username") ||
                    htmlAuto.contains("email") ||
                    htmlName.contains("user") ||
                    htmlName.contains("email") ||
                    htmlName.contains("login")
                )
                val text = node.autofillValue?.takeIf { it.isText }?.textValue?.toString().orEmpty()
                val isEdit = tag == "input" ||
                    node.className?.contains("EditText", true) == true ||
                    node.autofillType == View.AUTOFILL_TYPE_TEXT

                if (isPassword) {
                    passwordId = id
                    if (text.isNotEmpty()) passwordValue = text
                    if (!ids.contains(id)) ids += id
                } else if (isUsername) {
                    usernameId = id
                    if (text.isNotEmpty()) usernameValue = text
                    if (!ids.contains(id)) ids += id
                } else if (isEdit) {
                    textFields += id to text
                }
            }
        }

        if (passwordId != null && usernameId == null) {
            val other = textFields.lastOrNull()
            if (other != null) {
                usernameId = other.first
                if (usernameValue.isEmpty()) usernameValue = other.second
                if (!ids.contains(other.first)) ids += other.first
            }
        }

        if (domain.startsWith("www.")) domain = domain.removePrefix("www.")
        return AutofillFields(
            usernameId = usernameId,
            passwordId = passwordId,
            usernameValue = usernameValue,
            passwordValue = passwordValue,
            domain = domain.lowercase(),
            packageName = fallbackPackage,
            fillIds = ids.toTypedArray(),
        )
    }

    private fun walk(node: ViewNode, visit: (ViewNode) -> Unit) {
        visit(node)
        for (i in 0 until node.childCount) walk(node.getChildAt(i), visit)
    }
}
