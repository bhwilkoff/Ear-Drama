package com.example.appname.ui

import android.text.format.DateUtils
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.account.Accounts
import com.example.appname.account.StoredAccount

/**
 * ANDROID-DESIGN §4.11: the account is the Library's first row, never a
 * screen of its own and never asked for at launch. Signed out it reads "Sign
 * in to sync"; signed in, the provider and the last sync or the last error.
 * The row opens a sheet with the verbs. A TV never offers sign-in (§9.2), so
 * there the row exists only for an account already signed in on that device.
 */
@Composable
fun AccountRow(modifier: Modifier = Modifier) {
    val accounts = LocalAppContainer.current.accounts
    val account by accounts.account.collectAsState()
    val running by accounts.sync.running.collectAsState()
    val notice by accounts.notice.collectAsState()
    val television = LocalIsTelevision.current
    var open by rememberSaveable { mutableStateOf(false) }

    val current = account
    if (current == null && television) return
    val canSignIn = accounts.config.anySignIn
    val problem = if (current != null && !running) current.lastError else notice
    val haptics = rememberHaptics()
    val shown = remember { arrayOfNulls<String>(1) }
    LaunchedEffect(problem) {
        Haptic.forProblem(shown[0], problem)?.let(haptics)
        shown[0] = problem
    }

    ListItem(
        modifier = modifier.then(
            if (current != null || canSignIn) Modifier.tvFocusMark().clickable(onClickLabel = "Open account") { open = true } else Modifier,
        ),
        leadingContent = { Icon(Icons.Outlined.AccountCircle, contentDescription = null) },
        headlineContent = { Text(if (current == null) "Sign in to sync" else signedInWith(current)) },
        supportingContent = when {
            current == null && !canSignIn -> ({ Text("Sign-in is not set up in this build.") })
            problem != null -> ({ Text(problem, color = MaterialTheme.colorScheme.error) })
            current != null -> ({ Text(syncLine(current, running)) })
            else -> null
        },
    )
    if (open) AccountSheet(accounts, onDismiss = { open = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountSheet(accounts: Accounts, onDismiss: () -> Unit, why: String = "Sign in to sync") {
    val activity = LocalActivity.current
    val account by accounts.account.collectAsState()
    val running by accounts.sync.running.collectAsState()
    val busy by accounts.busy.collectAsState()
    val notice by accounts.notice.collectAsState()
    val television = LocalIsTelevision.current
    var confirming by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val current = account
            if (current == null) {
                Text(why, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                notice?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (!television && activity != null) {
                    if (accounts.config.googleReady) {
                        FilledTonalButton(onClick = { accounts.signInWithGoogle(activity) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Text("Sign in with Google")
                        }
                    }
                    if (accounts.config.appleReady) {
                        FilledTonalButton(onClick = { accounts.signInWithApple(activity) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Text("Sign in with Apple")
                        }
                    }
                }
            } else {
                Text(signedInWith(current), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Text(syncLine(current, running), style = MaterialTheme.typography.bodyMedium)
                current.lastError?.takeIf { !running }?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                notice?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                FilledTonalButton(onClick = accounts::syncNow, enabled = !running && !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("Sync now")
                }
                OutlinedButton(onClick = accounts::signOut, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("Sign out")
                }
                TextButton(onClick = { confirming = true }, enabled = !busy && activity != null, modifier = Modifier.fillMaxWidth()) {
                    Text("Delete account", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text("Delete your account?") },
            text = { Text("Your synced history, queue, and followed series are removed from the server. What is on this device stays.") },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    activity?.let(accounts::deleteAccount)
                }) {
                    Text("Delete account", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
        )
    }
}

private fun signedInWith(account: StoredAccount): String =
    if (account.provider == "apple") "Signed in with Apple" else "Signed in with Google"

private fun syncLine(account: StoredAccount, running: Boolean): String {
    if (running) return "Syncing"
    val at = account.lastSyncAt ?: return "Not synced yet"
    val now = System.currentTimeMillis()
    if (now - at < DateUtils.MINUTE_IN_MILLIS) return "Synced just now"
    return "Synced " + DateUtils.getRelativeTimeSpanString(at, now, DateUtils.MINUTE_IN_MILLIS)
}

/** The sign-in sheet at the moment a signed-out person acts (taking a part): [why] is the heading. Closes itself once signed in. */
@Composable
fun SignInSheet(why: String, onDismiss: () -> Unit) {
    val accounts = LocalAppContainer.current.accounts
    val account by accounts.account.collectAsState()
    LaunchedEffect(account != null) { if (account != null) onDismiss() }
    AccountSheet(accounts, onDismiss, why)
}
