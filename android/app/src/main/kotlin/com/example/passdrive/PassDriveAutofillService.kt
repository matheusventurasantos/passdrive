package com.example.passdrive

import android.app.assist.AssistStructure
import android.app.assist.AssistStructure.ViewNode
import android.app.PendingIntent
import android.content.Context
import android.os.SystemClock
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillContext
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.Presentations
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.service.autofill.SaveInfo
import android.widget.RemoteViews
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.inline.InlinePresentationSpec
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class PassDriveAutofillService : AutofillService() {
    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: android.os.CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val fields = FieldIds()
        var domain: String? = null
        for (windowIndex in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(windowIndex).rootViewNode
            walk(root, fields) { node ->
                if (domain.isNullOrBlank() && !node.webDomain.isNullOrBlank()) {
                    domain = node.webDomain
                }
            }
        }
        if (fields.username == null) {
            fields.username = fields.usernameFallback
            fields.usernameInferred = fields.username != null
        }
        // A bare text input (for example, a WhatsApp conversation) is not a
        // credential form. We only use the fallback username heuristic when a
        // password field exists; explicit username/email hints can stand alone
        // for multi-step login forms.
        if ((fields.username == null && fields.password == null) ||
            (fields.password == null && fields.usernameInferred)) {
            callback.onSuccess(null)
            return
        }

        val packageName = structure.activityComponent?.packageName.orEmpty()
        val inlineSpec = if (android.os.Build.VERSION.SDK_INT >= 30) {
            request.inlineSuggestionsRequest?.inlinePresentationSpecs?.firstOrNull()
        } else {
            null
        }
        val cached = cachedCredentialsFor(packageName, domain)
        if (cached.isNotEmpty()) {
            callback.onSuccess(buildResponse(fields, cached, inlineSpec))
            return
        }

        val requestId = UUID.randomUUID().toString()
        val pending = PendingRequest(
            callback = callback,
            username = fields.username,
            password = fields.password,
            authentication = true,
            inlineSpec = inlineSpec,
            context = this,
            packageName = packageName,
            domain = domain,
        )
        requests[requestId] = pending
        // Once the user taps the authentication suggestion, Android can
        // cancel the original fill request while it waits for the Activity
        // result. This request must survive that cancellation: it owns the
        // AutofillIds used to build the authenticated FillResponse.
        timeoutExecutor.schedule({
            requests.remove(requestId)?.let { expired ->
                if (!expired.authentication) expired.callback.onSuccess(null)
            }
        }, 2, TimeUnit.MINUTES)

        try {
            val authenticationIntent = android.content.Intent(this, MainActivity::class.java).apply {
                action = ACTION_AUTOFILL
                // This is an authentication Activity. It must be a new
                // instance so setResult() is delivered back to the Autofill
                // framework without closing/reusing the already open app.
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(EXTRA_REQUEST_ID, requestId)
                putExtra(EXTRA_PACKAGE, packageName)
                putExtra(EXTRA_DOMAIN, domain)
                putExtra(EXTRA_HAS_USERNAME, fields.username != null)
                putExtra(EXTRA_HAS_PASSWORD, fields.password != null)
            }
            val authentication = PendingIntent.getActivity(
                this,
                requestId.hashCode(),
                authenticationIntent,
                PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val presentation = presentation("Desbloquear PassDrive")
            val inlinePresentation = inlinePresentation(inlineSpec, "Desbloquear PassDrive")
            val ids = listOfNotNull(fields.username, fields.password).toTypedArray()
            val response = FillResponse.Builder()
            addSaveInfo(response, fields)
            if (android.os.Build.VERSION.SDK_INT >= 33 && inlinePresentation != null) {
                response.setAuthentication(
                    ids,
                    authentication.intentSender,
                    Presentations.Builder()
                        .setMenuPresentation(presentation)
                        .setInlinePresentation(inlinePresentation)
                        .build(),
                )
            } else if (android.os.Build.VERSION.SDK_INT >= 30 && inlinePresentation != null) {
                response.setAuthentication(
                    ids,
                    authentication.intentSender,
                    presentation,
                    inlinePresentation,
                    null,
                )
            } else {
                response.setAuthentication(ids, authentication.intentSender, presentation)
            }
            callback.onSuccess(response.build())
        } catch (_: Exception) {
            requests.remove(requestId)?.callback?.onFailure("Não foi possível abrir o PassDrive.")
        }
    }

    private fun cachedCredentialsFor(
        packageName: String,
        domain: String?,
    ): List<CachedCredential> {
        val availableCredentials = activeCachedCredentials()
        val normalizedDomain = hostOf(domain)
        val compactPackage = compact(packageName)
        // Some browser/IME combinations do not expose the web domain in the
        // AssistStructure. In that case the user still needs to be able to
        // choose a credential after unlocking the vault.
        if (normalizedDomain == null) {
            return availableCredentials.take(8)
        }
        val matched = availableCredentials.asSequence()
            .filter { credential ->
                val serviceHost = hostOf(credential.url)
                val domainMatches = normalizedDomain != null && serviceHost != null &&
                    (normalizedDomain == serviceHost ||
                        normalizedDomain.endsWith(".$serviceHost") ||
                        serviceHost.endsWith(".$normalizedDomain"))
                val packageMatches = compactPackage.isNotEmpty() &&
                    listOf(
                        compact(credential.name),
                        compact(credential.brand),
                        serviceHost?.substringBefore('.')?.let(::compact).orEmpty(),
                    ).any { token -> token.length >= 3 && compactPackage.contains(token) }
                domainMatches || packageMatches
            }
            .take(8)
            .toList()
        // Firefox can report an intermediary or redirect host rather than the
        // final login host. Once a credential form has been identified, keep
        // the chooser useful instead of sending the user back into an unlock
        // loop because a URL comparison was too strict.
        return if (matched.isEmpty()) availableCredentials.take(8) else matched
    }

    private fun buildResponse(
        fields: FieldIds,
        credentials: List<CachedCredential>,
        inlineSpec: InlinePresentationSpec?,
    ): FillResponse? {
        val response = FillResponse.Builder()
        addSaveInfo(response, fields)
        var datasetCount = 0
        credentials.forEach { credential ->
            val username = credential.username.ifBlank { credential.email }
            val password = credential.password
            val identity = credential.username.ifBlank { credential.email }
            val label = credential.name.ifBlank { "PassDrive" }.let { name ->
                if (identity.isBlank()) name else "$name — $identity"
            }
            val presentation = presentation(label)
            val inlinePresentation = inlinePresentation(inlineSpec, label)
            val dataset = Dataset.Builder(presentation)
            var hasValue = false
            fields.username?.let { id ->
                if (username.isNotEmpty()) {
                    setValue(dataset, id, username, presentation, inlinePresentation)
                    hasValue = true
                }
            }
            fields.password?.let { id ->
                if (password.isNotEmpty()) {
                    setValue(dataset, id, password, presentation, inlinePresentation)
                    hasValue = true
                }
            }
            if (hasValue) {
                response.addDataset(dataset.build())
                datasetCount++
            }
        }
        return if (datasetCount == 0) null else response.build()
    }

    private fun presentation(label: String): RemoteViews = RemoteViews(
        "com.example.passdrive",
        R.layout.autofill_suggestion,
    ).apply {
        setTextViewText(R.id.autofill_label, label)
    }

    private fun inlinePresentation(
        spec: InlinePresentationSpec?,
        label: String,
    ): InlinePresentation? {
        if (android.os.Build.VERSION.SDK_INT < 30 || spec == null) return null
        return createInlinePresentation(spec, label, this)
    }

    private fun setValue(
        dataset: Dataset.Builder,
        id: AutofillId,
        value: String,
        presentation: RemoteViews,
        inlinePresentation: InlinePresentation?,
    ) {
        if (android.os.Build.VERSION.SDK_INT >= 30 && inlinePresentation != null) {
            dataset.setValue(
                id,
                AutofillValue.forText(value),
                presentation,
                inlinePresentation,
            )
        } else {
            dataset.setValue(id, AutofillValue.forText(value), presentation)
        }
    }

    private fun hostOf(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        return try {
            val parsed = android.net.Uri.parse(
                if (trimmed.contains("://")) trimmed else "https://$trimmed",
            )
            parsed.host?.lowercase()?.removePrefix("www.")?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    private fun compact(value: String): String = value.lowercase()
        .filter { it in 'a'..'z' || it in '0'..'9' }

    private data class CachedCredential(
        val name: String,
        val brand: String,
        val url: String,
        val email: String,
        val username: String,
        val password: String,
    )

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess()
            return
        }
        val fields = FieldIds()
        var domain: String? = null
        for (index in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(index).rootViewNode, fields) { node ->
                if (domain.isNullOrBlank() && !node.webDomain.isNullOrBlank()) {
                    domain = node.webDomain
                }
            }
        }
        val username = fields.usernameValue?.trim().orEmpty()
        val password = fields.passwordValue.orEmpty()
        val packageName = structure.activityComponent?.packageName.orEmpty()
        // Android calls this only after the source app submits a form. Do not
        // turn a generic text input into a credential: the save path requires
        // one explicit/semantic login identity, exactly one real password
        // field, and no signup, confirmation, OTP or PIN signal.
        if (fields.canSaveLogin() &&
            packageName.isNotBlank() &&
            username.length in 1..512 &&
            password.length in 1..4096
        ) {
            try {
                val capture = AutofillSaveCaptureStore.Capture(
                    id = UUID.randomUUID().toString(),
                    packageName = packageName,
                    domain = hostOf(domain),
                    username = username,
                    password = password,
                )
                AutofillSaveCaptureStore.save(applicationContext, capture)
            } catch (_: Exception) {
                // A failed optional suggestion must not affect the source app.
            }
        }
        callback.onSuccess()
    }

    private fun addSaveInfo(response: FillResponse.Builder, fields: FieldIds) {
        val username = fields.username
        val password = fields.password
        if (username == null || password == null || !fields.canSaveLogin()) return
        response.setSaveInfo(
            SaveInfo.Builder(
                SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                arrayOf(username, password),
            ).build(),
        )
    }

    private fun walk(
        node: ViewNode,
        fields: FieldIds,
        onNode: (ViewNode) -> Unit,
    ) {
        onNode(node)
        for (childIndex in 0 until node.childCount) {
            walk(node.getChildAt(childIndex), fields, onNode)
        }
        val hints = node.autofillHints?.toSet().orEmpty()
        if (hints.any { it in NON_LOGIN_HINTS }) {
            fields.hasNonLoginSignal = true
        }
        val passwordLike = hints.any { it in PASSWORD_HINTS } || isPasswordField(node)
        if (passwordLike) {
            fields.passwordFieldCount++
            if (hints.any { it in LOGIN_PASSWORD_HINTS }) {
                fields.passwordHasLoginHint = true
            }
            if (isNonLoginPasswordField(node, hints) || isOtpOrPinField(node)) {
                fields.hasNonLoginSignal = true
            }
        }
        val id = node.autofillId ?: return
        if (fields.username == null && hints.any { it in USERNAME_HINTS }) {
            fields.username = id
            fields.usernameValue = node.autofillValue?.textValue?.toString()
            fields.usernameIsLoginContext = hints.any { it in LOGIN_USERNAME_HINTS }
        }
        if (fields.password == null && hints.any { it in PASSWORD_HINTS }) {
            if (!isNonLoginPasswordField(node, hints) && !isOtpOrPinField(node)) {
                fields.password = id
                fields.passwordValue = node.autofillValue?.textValue?.toString()
            }
        } else if (fields.password == null && isPasswordField(node)) {
            if (!isNonLoginPasswordField(node, hints) && !isOtpOrPinField(node)) {
                fields.password = id
                fields.passwordValue = node.autofillValue?.textValue?.toString()
            }
        }
        if (fields.username == null && isUsernameField(node)) {
            fields.username = id
            fields.usernameValue = node.autofillValue?.textValue?.toString()
            fields.usernameIsLoginContext = true
        }
        if (fields.usernameFallback == null && isTextInput(node) && !isPasswordField(node)) {
            fields.usernameFallback = id
            fields.usernameFallbackValue = node.autofillValue?.textValue?.toString()
        }
    }

    private fun isPasswordField(node: ViewNode): Boolean {
        val inputType = node.inputType
        if (inputType == 0) return false
        val variation = inputType and android.text.InputType.TYPE_MASK_VARIATION
        return variation == android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD ||
            variation == android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
            variation == android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD
    }

    private fun isUsernameField(node: ViewNode): Boolean {
        val hints = node.autofillHints?.toSet().orEmpty()
        val searchable = semanticText(node)
        if (hints.any { it in NON_LOGIN_HINTS } ||
            listOf(
                "new username",
                "new email",
                "confirm username",
                "confirm email",
                "repeat username",
                "repeat email",
                "create account",
                "signup",
                "sign up",
                "register",
            )
                .any(searchable::contains)
        ) {
            return false
        }
        return listOf("user", "email", "login", "account", "identifier")
            .any(searchable::contains)
    }

    private fun isNonLoginPasswordField(node: ViewNode, hints: Set<String>): Boolean {
        if (hints.any { it in NON_LOGIN_PASSWORD_HINTS }) return true
        val searchable = semanticText(node)
        return listOf(
            "new password",
            "create password",
            "change password",
            "confirm password",
            "repeat password",
            "retype password",
            "password confirmation",
        ).any(searchable::contains)
    }

    private fun isOtpOrPinField(node: ViewNode): Boolean {
        val inputType = node.inputType
        val variation = inputType and android.text.InputType.TYPE_MASK_VARIATION
        if (variation == android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD) return true
        val searchable = semanticText(node)
        return listOf(
            "otp",
            "one-time",
            "one time",
            "verification code",
            "authentication code",
            "auth code",
            "security code",
            "two-factor",
            "two factor",
            "2fa",
            "pin",
            "token",
        ).any(searchable::contains)
    }

    private fun semanticText(node: ViewNode): String = listOf(node.hint, node.idEntry)
        .filterNotNull()
        .joinToString(" ")
        .lowercase()
        .replace(Regex("[_-]+"), " ")

    private fun isTextInput(node: ViewNode): Boolean {
        val inputType = node.inputType
        if (inputType == 0) return false
        val inputClass = inputType and android.text.InputType.TYPE_MASK_CLASS
        return inputClass == android.text.InputType.TYPE_CLASS_TEXT ||
            inputClass == android.text.InputType.TYPE_CLASS_NUMBER
    }

    private class FieldIds {
        var username: AutofillId? = null
        var usernameValue: String? = null
        var usernameFallback: AutofillId? = null
        var usernameFallbackValue: String? = null
        var usernameInferred = false
        var usernameIsLoginContext = false
        var password: AutofillId? = null
        var passwordValue: String? = null
        var passwordHasLoginHint = false
        var passwordFieldCount = 0
        var hasNonLoginSignal = false

        fun canSaveLogin(): Boolean = username != null &&
            password != null &&
            usernameIsLoginContext &&
            passwordHasLoginHint &&
            passwordFieldCount == 1 &&
            !hasNonLoginSignal
    }

    private data class PendingRequest(
        val callback: FillCallback,
        val username: AutofillId?,
        val password: AutofillId?,
        val authentication: Boolean = false,
        val inlineSpec: InlinePresentationSpec? = null,
        val context: android.content.Context,
        val packageName: String,
        val domain: String?,
    )

    companion object {
        private const val ACTION_AUTOFILL = "com.example.passdrive.AUTOFILL"
        private const val EXTRA_REQUEST_ID = "passdrive_autofill_request"
        private const val EXTRA_PACKAGE = "passdrive_autofill_package"
        private const val EXTRA_DOMAIN = "passdrive_autofill_domain"
        private const val EXTRA_HAS_USERNAME = "passdrive_autofill_has_username"
        private const val EXTRA_HAS_PASSWORD = "passdrive_autofill_has_password"

        private val USERNAME_HINTS = setOf(
            "username",
            "emailAddress",
            "email",
            "newUsername",
        )
        private val LOGIN_USERNAME_HINTS = setOf(
            "username",
            "emailAddress",
            "email",
        )
        private val PASSWORD_HINTS = setOf(
            "password",
            "currentPassword",
            "newPassword",
        )
        private val LOGIN_PASSWORD_HINTS = setOf(
            "password",
            "currentPassword",
        )
        private val NON_LOGIN_PASSWORD_HINTS = setOf(
            "newPassword",
            "passwordConfirmation",
            "newPasswordConfirmation",
            "oneTimeCode",
            "smsOtp",
        )
        private val NON_LOGIN_HINTS = setOf(
            "newUsername",
            "newPassword",
            "passwordConfirmation",
            "newPasswordConfirmation",
            "oneTimeCode",
            "smsOtp",
        )
        private val requests = ConcurrentHashMap<String, PendingRequest>()
        private val timeoutExecutor: ScheduledExecutorService =
            Executors.newSingleThreadScheduledExecutor()
        @Volatile
        private var cachedCredentials: List<CachedCredential> = emptyList()
        @Volatile
        private var cachedCredentialsExpiresAt: Long = 0L
        private const val TRANSIENT_CACHE_MILLIS = 60_000L

        fun cache(credentials: List<Map<String, String>>, transient: Boolean = false) {
            cachedCredentials = credentials.mapNotNull { value ->
                val email = value["email"].orEmpty()
                val username = value["username"].orEmpty()
                val password = value["password"].orEmpty()
                if (email.isBlank() && username.isBlank() && password.isBlank()) {
                    null
                } else {
                    CachedCredential(
                        name = value["name"].orEmpty(),
                        brand = value["brand"].orEmpty(),
                        url = value["url"].orEmpty(),
                        email = email,
                        username = username,
                        password = password,
                    )
                }
            }.take(512)
            cachedCredentialsExpiresAt = if (transient) {
                SystemClock.elapsedRealtime() + TRANSIENT_CACHE_MILLIS
            } else {
                0L
            }
        }

        fun clearCache() {
            cachedCredentials = emptyList()
            cachedCredentialsExpiresAt = 0L
        }

        private fun activeCachedCredentials(): List<CachedCredential> {
            val expiresAt = cachedCredentialsExpiresAt
            if (expiresAt != 0L && SystemClock.elapsedRealtime() >= expiresAt) {
                cachedCredentials = emptyList()
                cachedCredentialsExpiresAt = 0L
            }
            return cachedCredentials
        }

        fun activityPayload(intent: android.content.Intent): Map<String, Any?>? {
            val id = intent.getStringExtra(EXTRA_REQUEST_ID) ?: return null
            val pending = requests[id] ?: return null
            val packageName = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
            val domain = intent.getStringExtra(EXTRA_DOMAIN)
            val hasUsername = intent.getBooleanExtra(EXTRA_HAS_USERNAME, false)
            val hasPassword = intent.getBooleanExtra(EXTRA_HAS_PASSWORD, false)
            // The Activity is exported for Android's Autofill framework. An
            // external app may forge extras, so only an active request with
            // the exact context captured by the service may cross the bridge.
            if (packageName != pending.packageName ||
                domain != pending.domain ||
                hasUsername != (pending.username != null) ||
                hasPassword != (pending.password != null)
            ) {
                return null
            }
            return mapOf(
                "id" to id,
                "packageName" to packageName,
                "domain" to domain,
                "hasUsername" to hasUsername,
                "hasPassword" to hasPassword,
            )
        }

        fun consumeSaveCapture(context: Context, id: String?): Map<String, String>? {
            val capture = AutofillSaveCaptureStore.consume(context, id) ?: return null
            return mapOf(
                "id" to capture.id,
                "packageName" to capture.packageName,
                "domain" to capture.domain.orEmpty(),
                "username" to capture.username,
                "password" to capture.password,
            )
        }

        fun pendingSaveCaptureId(context: Context): String? =
            AutofillSaveCaptureStore.pendingId(context)

        data class Completion(
            val requiresActivityResult: Boolean,
            val response: FillResponse?,
        )

        fun complete(
            requestId: String,
            credentials: List<Map<String, String>>,
        ): Completion {
            val pending = requests.remove(requestId)
            if (pending == null) {
                return Completion(false, null)
            }
            val authenticatedResponse = buildResponse(pending, credentials)
            if (pending.authentication) {
                return Completion(true, authenticatedResponse)
            }
            pending.callback.onSuccess(authenticatedResponse)
            return Completion(false, null)
        }

        private fun buildResponse(
            pending: PendingRequest,
            credentials: List<Map<String, String>>,
        ): FillResponse? {
            if (credentials.isEmpty()) return null
            val response = FillResponse.Builder()
            if (pending.username != null && pending.password != null) {
                response.setSaveInfo(
                    SaveInfo.Builder(
                        SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                        arrayOf(pending.username, pending.password),
                    ).build(),
                )
            }
            var datasetCount = 0
            credentials.forEach { credential ->
                val name = credential["name"].orEmpty().ifBlank { "PassDrive" }
                val username = credential["username"].orEmpty()
                val password = credential["password"].orEmpty()
                val label = if (username.isBlank()) name else "$name — $username"
                val presentation = presentationFor(label)
                val inlinePresentation = inlinePresentationFor(
                    pending.inlineSpec,
                    label,
                    pending.context,
                )
                val dataset = Dataset.Builder(presentation)
                var hasValue = false
                pending.username?.let { id ->
                    username.takeIf { it.isNotEmpty() }?.let { value ->
                        setValueFor(dataset, id, value, presentation, inlinePresentation)
                        hasValue = true
                    }
                }
                pending.password?.let { id ->
                    password.takeIf { it.isNotEmpty() }?.let { value ->
                        setValueFor(dataset, id, value, presentation, inlinePresentation)
                        hasValue = true
                    }
                }
                if (hasValue) {
                    response.addDataset(dataset.build())
                    datasetCount++
                }
            }
            return if (datasetCount == 0) null else response.build()
        }

        private fun presentationFor(label: String): RemoteViews = RemoteViews(
            "com.example.passdrive",
            R.layout.autofill_suggestion,
        ).apply {
            setTextViewText(R.id.autofill_label, label)
        }

        private fun inlinePresentationFor(
            spec: InlinePresentationSpec?,
            label: String,
            context: android.content.Context,
        ): InlinePresentation? {
            if (android.os.Build.VERSION.SDK_INT < 30 || spec == null) return null
            return createInlinePresentation(spec, label, context)
        }

        private fun setValueFor(
            dataset: Dataset.Builder,
            id: AutofillId,
            value: String,
            presentation: RemoteViews,
            inlinePresentation: InlinePresentation?,
        ) {
            if (android.os.Build.VERSION.SDK_INT >= 30 && inlinePresentation != null) {
                dataset.setValue(
                    id,
                    AutofillValue.forText(value),
                    presentation,
                    inlinePresentation,
                )
            } else {
                dataset.setValue(id, AutofillValue.forText(value), presentation)
            }
        }

        private fun createInlinePresentation(
            spec: InlinePresentationSpec,
            label: String,
            context: android.content.Context,
        ): InlinePresentation? {
            if (!UiVersions.getVersions(spec.style)
                    .contains(UiVersions.INLINE_UI_VERSION_1)
            ) {
                return null
            }
            val attribution = PendingIntent.getActivity(
                context,
                label.hashCode(),
                android.content.Intent(context, MainActivity::class.java).apply {
                    action = "com.example.passdrive.AUTOFILL_ATTRIBUTION"
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val content = InlineSuggestionUi.newContentBuilder(attribution)
                .setTitle(label)
                .setContentDescription("Credencial do PassDrive: $label")
                .build()
            return InlinePresentation(content.slice, spec, false)
        }
    }
}
