package com.leokwsw.googlelogin

import android.util.Base64
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class GoogleLogin : CordovaPlugin() {
    private val requestLock = Any()
    private val requestInProgress = AtomicBoolean(false)
    private val requestGeneration = AtomicInteger(0)
    private var currentUser: JSONObject? = null

    override fun execute(action: String, args: JSONArray, callbackContext: CallbackContext): Boolean {
        when (action) {
            "signIn" -> signIn(options(args), callbackContext, silent = false)
            "silentSignIn" -> signIn(options(args), callbackContext, silent = true)
            "signOut" -> clearSession(callbackContext)
            "disconnect" -> clearSession(callbackContext)
            "getCurrentUser" -> getCurrentUser(callbackContext)
            else -> return false
        }
        return true
    }

    override fun onReset() {
        synchronized(requestLock) {
            requestGeneration.incrementAndGet()
            requestInProgress.set(false)
        }
    }

    private fun signIn(options: JSONObject, callbackContext: CallbackContext, silent: Boolean) {
        if (hasScopes(options)) {
            fail(callbackContext, "SCOPES_UNSUPPORTED", "Android Sign in with Google does not accept extra OAuth scopes.")
            return
        }

        val webClientId = webClientId(options)
        if (webClientId == null) {
            fail(callbackContext, "MISSING_CLIENT_ID", "webClientId is required.")
            return
        }

        val activity = cordova.activity
        if (activity == null) {
            fail(callbackContext, "NO_ACTIVITY", "The activity is not available.")
            return
        }

        val generation = synchronized(requestLock) {
            if (!requestInProgress.compareAndSet(false, true)) {
                -1
            } else {
                requestGeneration.incrementAndGet()
            }
        }
        if (generation < 0) {
            fail(callbackContext, "REQUEST_IN_PROGRESS", "A Google sign-in request is already in progress.")
            return
        }
        val nonce = nonce(options)
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(if (silent) silentOption(webClientId, nonce) else buttonOption(webClientId, nonce))
            .build()

        activity.runOnUiThread {
            try {
                CredentialManager.create(activity).getCredentialAsync(
                    activity,
                    request,
                    null,
                    cordova.threadPool,
                    object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                        override fun onResult(result: GetCredentialResponse) {
                            if (!finishRequest(generation)) return
                            handleCredential(result, nonce, callbackContext)
                        }

                        override fun onError(e: GetCredentialException) {
                            if (!finishRequest(generation)) return
                            fail(callbackContext, codeFor(e), describe(e))
                        }
                    }
                )
            } catch (error: Exception) {
                if (!finishRequest(generation)) return
                fail(callbackContext, "SIGN_IN_FAILED", describe(error))
            }
        }
    }

    private fun clearSession(callbackContext: CallbackContext) {
        val activity = cordova.activity
        if (activity == null) {
            fail(callbackContext, "NO_ACTIVITY", "The activity is not available.")
            return
        }

        activity.runOnUiThread {
            CredentialManager.create(activity).clearCredentialStateAsync(
                ClearCredentialStateRequest(),
                null,
                cordova.threadPool,
                object : CredentialManagerCallback<Void?, ClearCredentialException> {
                    override fun onResult(result: Void?) {
                        setCurrentUser(null)
                        callbackContext.sendPluginResult(PluginResult(PluginResult.Status.OK, true))
                    }

                    override fun onError(e: ClearCredentialException) {
                        fail(callbackContext, "SIGN_IN_FAILED", describe(e))
                    }
                }
            )
        }
    }

    private fun getCurrentUser(callbackContext: CallbackContext) {
        val user = copyCurrentUser()
        if (user == null) {
            fail(callbackContext, "NOT_SIGNED_IN", "No Google user is signed in for this process.")
            return
        }
        callbackContext.success(user)
    }

    private fun handleCredential(result: GetCredentialResponse, nonce: String, callbackContext: CallbackContext) {
        val credential = result.credential
        if (credential !is CustomCredential ||
            credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            fail(callbackContext, "SIGN_IN_FAILED", "Google returned an unexpected credential.")
            return
        }

        val googleCredential = try {
            GoogleIdTokenCredential.createFrom(credential.data)
        } catch (error: GoogleIdTokenParsingException) {
            fail(callbackContext, "SIGN_IN_FAILED", describe(error))
            return
        }

        val idToken = googleCredential.idToken.trim()
        if (idToken.isEmpty()) {
            fail(callbackContext, "SIGN_IN_FAILED", "Google did not return an ID token.")
            return
        }

        val user = JSONObject()
        user.put("idToken", idToken)
        user.put("userId", textOrNull(googleCredential.uniqueId))
        user.put("email", textOrNull(googleCredential.email))
        user.put("displayName", textOrNull(googleCredential.displayName))
        user.put("givenName", textOrNull(googleCredential.givenName))
        user.put("familyName", textOrNull(googleCredential.familyName))
        user.put("photoUrl", textOrNull(googleCredential.profilePictureUri?.toString()))
        user.put("nonce", nonce)
        setCurrentUser(user)
        callbackContext.success(JSONObject(user.toString()))
    }

    private fun finishRequest(generation: Int): Boolean {
        synchronized(requestLock) {
            if (requestGeneration.get() != generation) {
                return false
            }
            requestInProgress.set(false)
            return true
        }
    }

    private fun setCurrentUser(user: JSONObject?) {
        synchronized(this) {
            currentUser = user
        }
    }

    private fun copyCurrentUser(): JSONObject? {
        synchronized(this) {
            val user = currentUser ?: return null
            return JSONObject(user.toString())
        }
    }

    private fun buttonOption(webClientId: String, nonce: String): GetSignInWithGoogleOption {
        return GetSignInWithGoogleOption.Builder(webClientId)
            .setNonce(nonce)
            .build()
    }

    private fun silentOption(webClientId: String, nonce: String): GetGoogleIdOption {
        return GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(true)
            .setServerClientId(webClientId)
            .setAutoSelectEnabled(true)
            .setNonce(nonce)
            .build()
    }

    private fun options(args: JSONArray): JSONObject {
        if (args.length() == 0 || args.isNull(0)) {
            return JSONObject()
        }
        return args.optJSONObject(0) ?: JSONObject()
    }

    private fun webClientId(options: JSONObject): String? {
        val fromOptions = options.optString("webClientId", "").trim()
        if (fromOptions.isNotEmpty()) {
            return fromOptions
        }
        val fromPreferences = preferences.getString("GoogleWebClientId", "").trim()
        return fromPreferences.ifEmpty { null }
    }

    private fun hasScopes(options: JSONObject): Boolean {
        if (!options.has("scopes") || options.isNull("scopes")) {
            return false
        }
        val scopes = options.optJSONArray("scopes") ?: return true
        return scopes.length() > 0
    }

    private fun nonce(options: JSONObject): String {
        val provided = options.optString("nonce", "").trim()
        if (provided.isNotEmpty()) {
            return provided
        }
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE or Base64.NO_PADDING)
    }

    private fun codeFor(error: GetCredentialException): String {
        if (error is GetCredentialCancellationException || error.type.contains("cancel", ignoreCase = true)) {
            return "CANCELED"
        }
        if (error is NoCredentialException || error.type.contains("no_credential", ignoreCase = true)) {
            return "NO_CREDENTIAL"
        }
        return "SIGN_IN_FAILED"
    }

    private fun fail(callbackContext: CallbackContext, code: String, message: String) {
        val payload = JSONObject()
        payload.put("code", code)
        payload.put("message", message)
        callbackContext.error(payload)
    }

    private fun describe(error: Exception): String {
        val text = error.message?.trim().orEmpty()
        return if (text.isEmpty()) error.javaClass.simpleName else text
    }

    private fun textOrNull(value: String?): Any {
        val text = value?.trim().orEmpty()
        return if (text.isEmpty()) JSONObject.NULL else text
    }
}
