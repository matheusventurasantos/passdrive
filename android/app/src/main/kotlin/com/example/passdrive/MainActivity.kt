package com.passdrive.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var syncChannel: MethodChannel? = null
    private var autofillChannel: MethodChannel? = null
    private var autofillReady = false
    private var pendingAutofill: Map<String, Any?>? = null
    private var pendingSaveCaptureId: String? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private val syncPrefs by lazy { getSharedPreferences("passdrive_sync", MODE_PRIVATE) }
    private var pendingSyncDevice: String? = null
    private var discoveryLock: android.net.wifi.WifiManager.MulticastLock? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("passdrive_sync_request")
            ?.takeIf { Regex("[A-Za-z0-9_-]{22}").matches(it) }
            ?.let {
            pendingSyncDevice = it
            syncChannel?.invokeMethod("pendingPairing", it)
        }
        PassDriveAutofillService.activityPayload(intent)?.let {
            pendingAutofill = it
            dispatchAutofillRequest()
        }
    }

    override fun onResume() {
        super.onResume()
        if (pendingSaveCaptureId == null) {
            pendingSaveCaptureId = PassDriveAutofillService.pendingSaveCaptureId(applicationContext)
        }
        dispatchAutofillSaveRequest()
    }

    private fun startDiscovery(): Boolean {
        val manager = getSystemService(android.app.NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        val service = Intent(this, LanDiscoveryService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        syncPrefs.edit().putBoolean("enabled", true).apply()
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 5101) {
            val result = notificationPermissionResult
            notificationPermissionResult = null
            try { result?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && startDiscovery()) }
            catch (e: Exception) { result?.error("sync_unavailable", "Não foi possível ativar as conexões em segundo plano.", null) }
        }
    }
    private val alias = "passdrive.biometric.v1"
    private val prefs by lazy { getSharedPreferences("vault_access", MODE_PRIVATE) }
    private var pending: MethodChannel.Result? = null
    private var output: ByteArray? = null
    private var pendingMaxBytes = 16384
    private var cancellation: CancellationSignal? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSyncDevice = intent.getStringExtra("passdrive_sync_request")
            ?.takeIf { Regex("[A-Za-z0-9_-]{22}").matches(it) }
        pendingAutofill = PassDriveAutofillService.activityPayload(intent)
        pendingSaveCaptureId =
            PassDriveAutofillService.pendingSaveCaptureId(applicationContext)
        syncChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "passdrive/sync").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "acquireDiscovery" -> {
                            if (discoveryLock?.isHeld != true) discoveryLock = (applicationContext.getSystemService(WIFI_SERVICE) as android.net.wifi.WifiManager).createMulticastLock("passdrive_unlocked").apply { setReferenceCounted(false); acquire() }
                            result.success(null)
                        }
                        "releaseDiscovery" -> { if (discoveryLock?.isHeld == true) discoveryLock?.release(); discoveryLock = null; result.success(null) }
                        "info" -> result.success(mapOf("name" to Build.MODEL.take(80), "enabled" to syncPrefs.getBoolean("enabled", false)))
                        "consumeRequest" -> { result.success(pendingSyncDevice); pendingSyncDevice = null; intent.removeExtra("passdrive_sync_request") }
                        "enableBackground" -> {
                            val id = call.argument<String>("id") ?: error("ID ausente")
                            require(Regex("[A-Za-z0-9_-]{22}").matches(id))
                            syncPrefs.edit().putString("id", id).putString("name", Build.MODEL.take(80)).apply()
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                if (notificationPermissionResult != null) { result.error("busy", "Aguarde a permissão atual.", null) }
                                else { notificationPermissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 5101) }
                            } else { result.success(startDiscovery()) }
                        }
                        "disableBackground" -> { syncPrefs.edit().putBoolean("enabled", false).apply(); stopService(Intent(this, LanDiscoveryService::class.java)); result.success(false) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("sync_unavailable", "Não foi possível preparar a conexão local.", null) }
            }
        }
        autofillChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "passdrive/autofill").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "ready" -> {
                            autofillReady = true
                            // A newly-created authentication Activity can
                            // receive its request before Flutter installs the
                            // outbound method-call listener. Return the first
                            // payload directly to make this handoff reliable.
                            val payload = pendingAutofill
                            pendingAutofill = null
                            result.success(payload)
                            window.decorView.post { dispatchAutofillSaveRequest() }
                        }
                        "consumeSaveCaptureId" -> {
                            val id = pendingSaveCaptureId
                            pendingSaveCaptureId = null
                            result.success(id)
                        }
                        "consumeSaveCapture" -> {
                            val id = call.argument<String>("id")
                            result.success(
                                PassDriveAutofillService.consumeSaveCapture(
                                    applicationContext,
                                    id,
                                ),
                            )
                        }
                        "enabled" -> result.success(isAutofillEnabled())
                        "openSettings" -> {
                            if (Build.VERSION.SDK_INT < 26) {
                                result.success(false)
                            } else {
                                startActivity(Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                })
                                result.success(true)
                            }
                        }
                        "disable" -> {
                            if (Build.VERSION.SDK_INT >= 26) {
                                getSystemService(android.view.autofill.AutofillManager::class.java)
                                    ?.disableAutofillServices()
                            }
                            result.success(false)
                        }
                        "cache" -> {
                            val rawCredentials = call.argument<List<Any?>>("credentials").orEmpty()
                            val transient = call.argument<Boolean>("transient") ?: false
                            val credentials = rawCredentials.mapNotNull { raw: Any? ->
                                val map = raw as? Map<*, *> ?: return@mapNotNull null
                                mapOf(
                                    "name" to (map["name"] as? String).orEmpty(),
                                    "brand" to (map["brand"] as? String).orEmpty(),
                                    "url" to (map["url"] as? String).orEmpty(),
                                    "email" to (map["email"] as? String).orEmpty(),
                                    "username" to (map["username"] as? String).orEmpty(),
                                    "password" to (map["password"] as? String).orEmpty(),
                                )
                            }
                            PassDriveAutofillService.cache(credentials, transient)
                            result.success(null)
                        }
                        "clear" -> {
                            PassDriveAutofillService.clearCache()
                            result.success(null)
                        }
                        "complete" -> {
                            val requestId = call.argument<String>("id") ?: error("ID ausente")
                            val rawCredentials = call.argument<List<Any?>>("credentials").orEmpty()
                            val credentials = rawCredentials.mapNotNull { raw: Any? ->
                                val map = raw as? Map<*, *> ?: return@mapNotNull null
                                mapOf(
                                    "name" to (map["name"] as? String).orEmpty(),
                                    "username" to (map["username"] as? String).orEmpty(),
                                    "password" to (map["password"] as? String).orEmpty(),
                                )
                            }
                            val completion =
                                PassDriveAutofillService.complete(requestId, credentials)
                            // Reply to Dart before closing this temporary
                            // authentication Activity. Finishing first can
                            // tear down the Flutter engine before the pending
                            // invokeMethod future receives its result.
                            result.success(completion.requiresActivityResult)
                            if (completion.requiresActivityResult) {
                                val reply = Intent()
                                completion.response?.let { response ->
                                    reply.putExtra(
                                        android.view.autofill.AutofillManager.EXTRA_AUTHENTICATION_RESULT,
                                        response,
                                    )
                                    setResult(Activity.RESULT_OK, reply)
                                } ?: setResult(Activity.RESULT_CANCELED)
                                window.decorView.post { finish() }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("autofill_unavailable", "Não foi possível concluir o preenchimento automático.", null)
                }
            }
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "passdrive/access")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "Uma operação já está em andamento.", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "enabled" -> result.success(prefs.contains("cipher"))
                        "disable" -> {
                            clearBiometric()
                            result.success(null)
                        }
                        "setScreenCaptureAllowed" -> {
                            val allowed = call.argument<Boolean>("allowed") ?: false
                            if (allowed) {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        }
                        "enable", "unlock" -> biometric(call.method == "enable", call.argument<ByteArray>("key"), result)
                        "save" -> {
                            output = call.argument<ByteArray>("bytes") ?: error("Arquivo vazio")
                            pending = result
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                type = "application/octet-stream"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename") ?: "passdrive-chave-mestra.pdkey")
                            }, 4101)
                        }
                        "pick" -> {
                            pendingMaxBytes = (call.argument<Int>("maxBytes") ?: 16384).coerceIn(1, 5 * 1024 * 1024)
                            pending = result
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                type = "*/*"
                            }, 4102)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    output?.fill(0)
                    output = null
                    pending = null
                    result.error("access_failed", "Não foi possível concluir esta operação.", null)
                }
            }
    }

    private fun dispatchAutofillRequest() {
        val payload = pendingAutofill ?: return
        if (!autofillReady) return
        pendingAutofill = null
        autofillChannel?.invokeMethod("request", payload)
    }

    private fun dispatchAutofillSaveRequest() {
        val id = pendingSaveCaptureId ?: return
        if (!autofillReady) return
        pendingSaveCaptureId = null
        autofillChannel?.invokeMethod("saveRequest", mapOf("id" to id))
    }

    private fun isAutofillEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        val manager = getSystemService(android.view.autofill.AutofillManager::class.java)
        val component = manager?.autofillServiceComponentName ?: return false
        return component.packageName == packageName &&
            component.className == PassDriveAutofillService::class.java.name
    }

    private fun store(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun clearBiometric() {
        prefs.edit().clear().commit()
        store().deleteEntry(alias)
    }

    private fun biometric(enroll: Boolean, bytes: ByteArray?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 28) {
            result.error("unavailable", "Use a senha ou o arquivo neste aparelho.", null)
            return
        }
        if (enroll && bytes?.size != 32) {
            result.error("invalid_key", "Chave inválida.", null)
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            if (enroll) {
                clearBiometric()
                val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true)
                    .build())
                cipher.init(Cipher.ENCRYPT_MODE, generator.generateKey())
            } else {
                val key = store().getKey(alias, null) as? SecretKey ?: error("No biometric key")
                val iv = Base64.decode(prefs.getString("iv", null) ?: error("No IV"), Base64.NO_WRAP)
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            }
        } catch (e: Exception) {
            clearBiometric()
            bytes?.fill(0)
            result.error("unavailable", "Ative a biometria novamente usando sua senha ou arquivo.", null)
            return
        }
        pending = result
        val signal = CancellationSignal()
        cancellation = signal
        val prompt = BiometricPrompt.Builder(this)
            .setTitle(if (enroll) "Ativar biometria" else "Desbloquear PassDrive")
            .setSubtitle("Confirme sua identidade para acessar o cofre")
            .setNegativeButton("Usar senha ou arquivo", mainExecutor) { _, _ ->
                val reply = pending
                pending = null
                cancellation?.cancel()
                cancellation = null
                bytes?.fill(0)
                if (enroll) clearBiometric()
                reply?.error("cancelled", "Use a senha ou o arquivo para entrar.", null)
            }
            .build()
        prompt.authenticate(BiometricPrompt.CryptoObject(cipher), signal, mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(authentication: BiometricPrompt.AuthenticationResult) {
                    val reply = pending ?: return
                    pending = null
                    cancellation = null
                    try {
                        val authorizedCipher = authentication.cryptoObject?.cipher ?: error("Missing cipher")
                        if (enroll) {
                            val encrypted = authorizedCipher.doFinal(bytes!!)
                            check(prefs.edit()
                                .putString("iv", Base64.encodeToString(authorizedCipher.iv, Base64.NO_WRAP))
                                .putString("cipher", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
                            reply.success(true)
                        } else {
                            val encrypted = Base64.decode(prefs.getString("cipher", null), Base64.NO_WRAP)
                            reply.success(authorizedCipher.doFinal(encrypted))
                        }
                    } catch (e: Exception) {
                        clearBiometric()
                        reply.error("unavailable", "Use a senha ou o arquivo para entrar.", null)
                    } finally { bytes?.fill(0) }
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    val reply = pending ?: return
                    pending = null
                    cancellation = null
                    bytes?.fill(0)
                    if (enroll) clearBiometric()
                    val cancelled = code == BiometricPrompt.BIOMETRIC_ERROR_CANCELED ||
                        code == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED
                    reply.error(if (cancelled) "cancelled" else "biometric_failed",
                        if (cancelled) "Use a senha ou o arquivo para entrar." else message.toString(), null)
                }
            })
    }

    @Deprecated("Used by Flutter activity result dispatch")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4101 && requestCode != 4102) return
        val reply = pending ?: return
        pending = null
        try {
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                reply.success(null)
            } else if (requestCode == 4101) {
                val bytesToSave = output ?: error("No output")
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytesToSave) }
                    ?: error("No stream")
                // A provider is external input. Bound the verification read so
                // a faulty provider cannot turn the post-write check into an
                // unbounded allocation.
                val saved = contentResolver.openInputStream(uri)?.use { input ->
                    val buffer = ByteArray(bytesToSave.size + 1)
                    var count = 0
                    while (count < buffer.size) {
                        val read = input.read(buffer, count, buffer.size - count)
                        if (read <= 0) break
                        count += read
                    }
                    buffer.copyOf(count)
                }
                    ?: error("No saved stream")
                if (saved.size != bytesToSave.size || !saved.contentEquals(bytesToSave)) {
                    error("Saved file does not match")
                }
                reply.success(true)
            } else {
                if (data.flags.and(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0) {
                    data.flags.and(Intent.FLAG_GRANT_READ_URI_PERMISSION).takeIf { it != 0 }?.let {
                        contentResolver.takePersistableUriPermission(uri, it)
                    }
                }
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val buffer = ByteArray(pendingMaxBytes + 1)
                    var count = 0
                    while (count < buffer.size) {
                        val read = input.read(buffer, count, buffer.size - count)
                        if (read <= 0) break
                        count += read
                    }
                    buffer.copyOf(count)
                } ?: error("No stream")
                if (bytes.size > pendingMaxBytes) reply.error("invalid_file", "O arquivo selecionado é grande demais.", null)
                else reply.success(bytes)
            }
        } catch (e: Exception) {
            reply.error("file_failed", "Não foi possível ler ou salvar o arquivo.", null)
        } finally {
            output?.fill(0)
            output = null
        }
    }
}
