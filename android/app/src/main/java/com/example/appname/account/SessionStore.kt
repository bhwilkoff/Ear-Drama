package com.example.appname.account

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Where the signed-in account lives between launches. */
interface SessionStore {
    fun load(): StoredAccount?

    /** Null forgets the account entirely. */
    fun save(account: StoredAccount?)
}

/**
 * The account record, AES-256-GCM encrypted under a key that never leaves the
 * Android Keystore, in one file under `noBackupFilesDir` (AGENTS.md: secrets
 * never in cleartext on disk; no plain SharedPreferences). The file is the IV
 * then the ciphertext. A file that will not decrypt (the key was cleared, or a
 * restore from another device) reads as signed out and is removed.
 */
class KeystoreSessionStore(private val file: File) : SessionStore {

    private companion object {
        const val ALIAS = "eardrama.session"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }

    override fun load(): StoredAccount? {
        if (!file.isFile) return null
        return try {
            val bytes = file.readBytes()
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
            val plain = cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES)
            WorkerJson.decodeFromString<StoredAccount>(plain.decodeToString())
        } catch (e: Exception) {
            println("KeystoreSessionStore: unreadable account file, signed out (${e.javaClass.simpleName})")
            file.delete()
            null
        }
    }

    override fun save(account: StoredAccount?) {
        if (account == null) {
            file.delete()
            return
        }
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(WorkerJson.encodeToString(account).encodeToByteArray())
        file.parentFile?.mkdirs()
        val tmp = File(file.path + ".tmp")
        tmp.writeBytes(sealed)
        if (!tmp.renameTo(file)) {
            tmp.delete()
            error("could not replace ${file.name}")
        }
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
