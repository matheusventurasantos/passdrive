package com.passdrive.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * A short-lived, encrypted handoff between Android's Autofill save callback
 * and the unlocked Flutter vault. The credential is never placed in a
 * notification, log, Intent extra, or unencrypted preference.
 */
internal object AutofillSaveCaptureStore {
    private const val PREFS = "passdrive_autofill_save_capture"
    private const val KEY_ALIAS = "passdrive.autofill.save.capture.v1"
    private const val KEY_IV = "iv"
    private const val KEY_CIPHER = "cipher"
    private const val KEY_ID = "id"
    private const val KEY_EXPIRES = "expires"
    private const val LIFETIME_MILLIS = 15 * 60 * 1000L

    data class Capture(
        val id: String,
        val packageName: String,
        val domain: String?,
        val username: String,
        val password: String,
    )

    fun save(context: Context, capture: Capture) {
        val plain = JSONObject()
            .put("packageName", capture.packageName)
            .put("domain", capture.domain ?: JSONObject.NULL)
            .put("username", capture.username)
            .put("password", capture.password)
            .toString()
            .toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val encrypted = cipher.doFinal(plain)
            check(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_ID, capture.id)
                .putLong(KEY_EXPIRES, System.currentTimeMillis() + LIFETIME_MILLIS)
                .putString(KEY_IV, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .putString(KEY_CIPHER, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .commit())
        } finally {
            plain.fill(0)
        }
    }

    fun consume(context: Context, id: String?): Capture? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val storedId = prefs.getString(KEY_ID, null)
        val expires = prefs.getLong(KEY_EXPIRES, 0L)
        if (id.isNullOrBlank() || storedId != id || expires < System.currentTimeMillis()) {
            if (expires != 0L && expires < System.currentTimeMillis()) clear(context)
            return null
        }
        val iv = prefs.getString(KEY_IV, null)
        val encrypted = prefs.getString(KEY_CIPHER, null)
        if (iv.isNullOrBlank() || encrypted.isNullOrBlank()) {
            clear(context)
            return null
        }
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                key(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)),
            )
            val plain = cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP))
            try {
                val json = JSONObject(String(plain, Charsets.UTF_8))
                Capture(
                    id = id,
                    packageName = json.optString("packageName"),
                    domain = json.optString("domain").takeIf { it.isNotBlank() && it != "null" },
                    username = json.optString("username"),
                    password = json.optString("password"),
                )
            } finally {
                plain.fill(0)
            }
        } catch (_: Exception) {
            null
        } finally {
            clear(context)
        }
    }

    fun pendingId(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val expires = prefs.getLong(KEY_EXPIRES, 0L)
        if (expires < System.currentTimeMillis()) {
            if (expires != 0L) clear(context)
            return null
        }
        return prefs.getString(KEY_ID, null)
    }

    private fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
            generateKey()
        }
    }
}
