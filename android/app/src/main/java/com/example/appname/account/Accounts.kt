package com.example.appname.account

import android.app.Activity
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * The account verbs the Library's account row offers (ANDROID-DESIGN §4.11):
 * sign in with Google or Apple, Sync now, sign out, delete the account. Sign-in
 * is optional and never asked for at launch (DECISIONS 057): nothing here runs
 * until the person opens the row, except a sync when a signed-in app starts or
 * goes to the background.
 */
class Accounts(
    val worker: WorkerApi,
    val sync: SyncEngine,
    private val device: String,
    private val scope: CoroutineScope,
) {
    val account: StateFlow<StoredAccount?> = worker.account
    val config: WorkerConfig get() = worker.config

    private val _busy = MutableStateFlow(false)

    /** A sign-in, sign-out, or deletion is under way. */
    val busy: StateFlow<Boolean> = _busy

    private val _notice = MutableStateFlow<String?>(null)

    /** Why the last sign-in or deletion did not finish, until the next attempt. */
    val notice: StateFlow<String?> = _notice

    @Volatile private var pendingApple: AppleWebSignIn.Pending? = null

    fun signInWithGoogle(activity: Activity) {
        if (!config.googleReady) return
        verb {
            val token = GoogleSignIn.token(activity, config.googleWebClientId)
            worker.signIn("google", token.idToken, token.nonce, device)
            sync.sync()
        }
    }

    fun signInWithApple(activity: Activity) {
        if (!config.appleReady) return
        startApple(activity, forDeletion = false)
    }

    /**
     * Deletes the account after the person confirmed. An Apple account first
     * goes back through Apple for a fresh authorization code, which the Worker
     * uses to revoke the Apple token; the deletion finishes in [handleCallback].
     */
    fun deleteAccount(activity: Activity) {
        val current = account.value ?: return
        if (current.provider == "apple" && config.appleReady) {
            startApple(activity, forDeletion = true)
        } else {
            verb { worker.deleteAccount() }
        }
    }

    fun syncNow() {
        scope.launch { sync.sync() }
    }

    fun signOut() {
        verb { worker.signOut() }
    }

    /** `eardrama://oauth/apple#...` from the return page. True when the link was this flow's. */
    fun handleCallback(url: String): Boolean {
        val callback = AppleWebSignIn.parse(url) ?: return false
        val pending = pendingApple
        pendingApple = null
        when {
            pending == null || callback.state != pending.state -> _notice.value = "Apple sign-in did not finish."
            callback.error != null -> if (callback.error != "user_cancelled_authorize") {
                _notice.value = "Apple sign-in did not finish."
            }
            pending.forDeletion -> verb {
                worker.deleteAccount(appleAuthorizationCode = callback.code, appleClientId = config.appleServicesId)
            }
            callback.idToken == null -> _notice.value = "Apple sign-in did not finish."
            else -> verb {
                worker.signIn("apple", callback.idToken, pending.nonce, device)
                sync.sync()
            }
        }
        return true
    }

    private fun startApple(activity: Activity, forDeletion: Boolean) {
        val pending = AppleWebSignIn.Pending(state = randomToken(), nonce = randomToken(), forDeletion = forDeletion)
        pendingApple = pending
        _notice.value = null
        AppleWebSignIn.open(activity, AppleWebSignIn.authorizeUrl(config, pending))
    }

    private fun verb(block: suspend () -> Unit) {
        if (_busy.value) return
        _busy.value = true
        _notice.value = null
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: SignInStopped) {
                _notice.value = e.message
            } catch (e: Exception) {
                println("Accounts: ${e.javaClass.simpleName}: ${e.message}")
                _notice.value = when (e) {
                    is WorkerException -> "The server answered ${e.status}."
                    is IOException -> "No connection to the server."
                    else -> "That did not finish."
                }
            } finally {
                _busy.value = false
            }
        }
    }
}
