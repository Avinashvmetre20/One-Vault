package com.example.one_vault.autofill

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class StoredLogin(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val domain: String,
    val website: String,
) {
    fun toMap(): Map<String, String> = mapOf(
        "id" to id,
        "title" to title,
        "username" to username,
        "password" to password,
        "domain" to domain,
        "website" to website,
    )
}

object AutofillStore {
    private const val PREFS = "onevault_autofill"
    private const val BLOB = "blob"
    private const val KEY_ALIAS = "onevault_autofill_aes"

    fun match(context: Context, domain: String): List<StoredLogin> {
        val host = normalize(domain)
        if (host.isEmpty()) return emptyList()
        return load(context).filter { item ->
            val itemHost = normalize(item.domain)
            itemHost.isNotEmpty() &&
                (itemHost == host || itemHost.endsWith(".$host") || host.endsWith(".$itemHost"))
        }
    }

    fun saveLogin(context: Context, username: String, password: String, domain: String) {
        if (password.isEmpty()) return
        val host = normalize(domain)
        val items = load(context).toMutableList()
        val pending = pendingIds(context).toMutableSet()
        val index = items.indexOfFirst {
            it.domain == host && it.username.equals(username, true) && username.isNotEmpty()
        }
        val id = if (index >= 0) items[index].id else UUID.randomUUID().toString()
        val item = StoredLogin(
            id = id,
            title = host.ifEmpty { "Login" },
            username = username,
            password = password,
            domain = host,
            website = if (host.isEmpty()) "" else "https://$host",
        )
        if (index >= 0) items[index] = item else items += item
        pending += id
        write(context, items, pending)
    }

    fun pending(context: Context): List<StoredLogin> {
        val pending = pendingIds(context)
        if (pending.isEmpty()) return emptyList()
        return load(context).filter { it.id in pending }
    }

    fun syncFromVault(context: Context, vaultItems: List<StoredLogin>) {
        val pending = pendingIds(context)
        val pendingItems = load(context).filter { it.id in pending }
        val merged = vaultItems.associateBy { it.id }.toMutableMap()
        for (item in pendingItems) {
            val duplicate = merged.values.any {
                it.domain == item.domain &&
                    it.username.equals(item.username, true) &&
                    item.username.isNotEmpty()
            }
            if (!merged.containsKey(item.id) && !duplicate) {
                merged[item.id] = item
            }
        }
        val keptPending = pending.filter { id ->
            merged.containsKey(id) && vaultItems.none { it.id == id }
        }.toSet()
        write(context, merged.values.toList(), keptPending)
    }

    fun clear(context: Context) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    private fun load(context: Context): List<StoredLogin> = snapshot(context).first

    private fun pendingIds(context: Context): Set<String> = snapshot(context).second

    private fun snapshot(context: Context): Pair<List<StoredLogin>, Set<String>> {
        return try {
            val raw = context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(BLOB, null)
                ?: return emptyList<StoredLogin>() to emptySet()
            val json = JSONObject(decrypt(raw))
            val items = json.optJSONArray("items") ?: JSONArray()
            val parsed = buildList {
                for (i in 0 until items.length()) {
                    val obj = items.optJSONObject(i) ?: continue
                    add(
                        StoredLogin(
                            id = obj.optString("id"),
                            title = obj.optString("title"),
                            username = obj.optString("username"),
                            password = obj.optString("password"),
                            domain = normalize(obj.optString("domain")),
                            website = obj.optString("website"),
                        ),
                    )
                }
            }
            val pending = json.optJSONArray("pending") ?: JSONArray()
            val ids = buildSet {
                for (i in 0 until pending.length()) add(pending.optString(i))
            }
            parsed to ids
        } catch (_: Exception) {
            emptyList<StoredLogin>() to emptySet()
        }
    }

    private fun write(context: Context, items: List<StoredLogin>, pending: Set<String>) {
        val payload = JSONObject()
            .put(
                "items",
                JSONArray().also { array ->
                    items.forEach { item ->
                        array.put(
                            JSONObject()
                                .put("id", item.id)
                                .put("title", item.title)
                                .put("username", item.username)
                                .put("password", item.password)
                                .put("domain", item.domain)
                                .put("website", item.website),
                        )
                    }
                },
            )
            .put("pending", JSONArray(pending.toList()))
            .toString()
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(BLOB, encrypt(payload))
            .apply()
    }

    private fun normalize(domain: String): String {
        var host = domain.trim().lowercase()
        if (host.startsWith("www.")) host = host.removePrefix("www.")
        return host
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val data = Base64.encodeToString(cipher.doFinal(plain.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        return "$iv.$data"
    }

    private fun decrypt(blob: String): String {
        val parts = blob.split(".", limit = 2)
        if (parts.size != 2) return "{}"
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        return String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
    }
}
