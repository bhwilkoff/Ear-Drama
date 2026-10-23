package com.example.appname.account

import android.app.Activity
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import android.util.Base64
import java.net.URLDecoder
import java.security.SecureRandom

/** A random value for a nonce or a state: 32 bytes, base64url without padding. */
fun randomToken(): String {
    val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
    return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
}

/** What a provider handed back, ready for the Worker. */
data class ProviderToken(val idToken: String, val nonce: String)

/** A sign-in the person stopped (cancelled, or no account) is not an error. */
class SignInStopped(message: String?) : Exception(message)

/**
 * Sign in with Google through Credential Manager's "Sign in with Google"
 * button flow, asking for an ID token addressed to the Web client id (the
 * Worker's `GOOGLE_AUDIENCES` holds that one; docs/WORKER.md step 6) and
 * bound to a fresh raw nonce, which Google puts in the token as sent.
 */
object GoogleSignIn {
    suspend fun token(activity: Activity, webClientId: String): ProviderToken {
        val nonce = randomToken()
        val option = GetSignInWithGoogleOption.Builder(webClientId).setNonce(nonce).build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val credential = try {
            CredentialManager.create(activity).getCredential(activity, request).credential
        } catch (e: GetCredentialCancellationException) {
            throw SignInStopped(null)
        } catch (e: NoCredentialException) {
            throw SignInStopped("No Google account is on this device.")
        } catch (e: GetCredentialException) {
            throw SignInStopped("Google sign-in did not finish.")
        }
        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            throw SignInStopped("Google sign-in did not finish.")
        }
        return ProviderToken(GoogleIdTokenCredential.createFrom(credential.data).idToken, nonce)
    }
}

/**
 * Sign in with Apple on Android: Apple's web authorization in a Custom Tab.
 * No scope is asked (no name, no email: the Worker stores neither), which is
 * what lets Apple answer in the URL fragment rather than a form POST. Apple
 * returns to the Services ID's https return URL, whose page forwards the
 * fragment to `eardrama://oauth/apple` (DEEP_LINKS.md), and MainActivity hands
 * that link to [Accounts.handleCallback].
 *
 * `response_type=code id_token`: the id token signs in; the code is what
 * account deletion sends so the Worker can revoke the Apple token.
 */
object AppleWebSignIn {
    const val CALLBACK_PREFIX = "eardrama://oauth/apple"

    data class Pending(val state: String, val nonce: String, val forDeletion: Boolean)

    data class Callback(val state: String?, val idToken: String?, val code: String?, val error: String?)

    fun authorizeUrl(config: WorkerConfig, pending: Pending): String =
        Uri.parse("https://appleid.apple.com/auth/authorize").buildUpon()
            .appendQueryParameter("client_id", config.appleServicesId)
            .appendQueryParameter("redirect_uri", config.appleReturnUrl)
            .appendQueryParameter("response_type", "code id_token")
            .appendQueryParameter("response_mode", "fragment")
            .appendQueryParameter("state", pending.state)
            .appendQueryParameter("nonce", pending.nonce)
            .build().toString()

    fun open(activity: Activity, url: String) {
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, Uri.parse(url))
    }

    /** The forwarded answer, from the fragment or the query (either may carry it). */
    fun parse(url: String): Callback? {
        if (!url.startsWith(CALLBACK_PREFIX)) return null
        val params = (url.substringAfter('#', "") + "&" + url.substringAfter('?', "").substringBefore('#'))
            .split('&')
            .filter { '=' in it }
            .associate { decode(it.substringBefore('=')) to decode(it.substringAfter('=')) }
        return Callback(params["state"], params["id_token"], params["code"], params["error"])
    }

    private fun decode(s: String): String = URLDecoder.decode(s, "UTF-8")
}
