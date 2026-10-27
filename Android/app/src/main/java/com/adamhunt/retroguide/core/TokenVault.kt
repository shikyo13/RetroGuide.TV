package com.adamhunt.retroguide.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Server access tokens, encrypted with a key that never leaves the Android
 * Keystore (the Keychain's counterpart). Stored as IV + ciphertext in one file.
 */
class TokenVault(context: Context) {
    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "retroguide.tokens"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG_BITS = 128
        const val IV_BYTES = 12
        const val KEY_BITS = 256
        const val FILE_NAME = "tokens.bin"
    }

    private val file = File(context.noBackupFilesDir, FILE_NAME)
    private val serializer = MapSerializer(String.serializer(), String.serializer())

    fun load(): Map<String, String> = runCatching {
        if (!file.exists()) return emptyMap()
        val bytes = file.readBytes()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
        val plain = cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES)
        Json.decodeFromString(serializer, plain.decodeToString())
    }.getOrDefault(emptyMap())

    fun save(tokens: Map<String, String>) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(Json.encodeToString(serializer, tokens).encodeToByteArray())
        val temporary = File(file.parentFile, "$FILE_NAME.tmp")
        temporary.writeBytes(sealed)
        temporary.renameTo(file)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KEY_BITS)
                .build(),
        )
        return generator.generateKey()
    }
}
