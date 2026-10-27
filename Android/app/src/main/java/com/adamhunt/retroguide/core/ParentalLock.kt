package com.adamhunt.retroguide.core

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.MessageDigest
import java.util.UUID

/**
 * The parental PIN (the Apple app's `ParentalControls` lock): a salted
 * SHA-256 verifier kept in its own Keystore-encrypted vault, five tries before
 * a one-minute wait, and an unlock that lasts until Settings close. The policy
 * itself lives in the core.
 */
class ParentalLock(context: Context) {
    object Limits {
        /** The Kit's `ParentalPIN.length`. */
        const val PIN_LENGTH = 4
        const val ATTEMPTS = 5
        const val COOLDOWN_MS = 60_000L
    }

    private object Field {
        const val SALT = "salt"
        const val VERIFIER = "verifier"
        const val FAILED = "failedAttempts"
        const val RETRY_AFTER = "retryAfter"
    }

    private companion object {
        const val VAULT = "parental.bin"
        const val DIGEST = "SHA-256"
    }

    private val vault = TokenVault(context, VAULT)
    private var record: Map<String, String> = vault.load()

    /** The vault was written before but can't be read: restrictions stay on and Settings stay locked. */
    val isUnavailable = vault.exists && record.isEmpty()
    val hasPIN get() = record.containsKey(Field.VERIFIER)

    private val _isAuthorized = MutableStateFlow(false)
    val isAuthorized: StateFlow<Boolean> = _isAuthorized.asStateFlow()
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    fun isValid(pin: String) = pin.length == Limits.PIN_LENGTH && pin.all(Char::isDigit)

    fun authorize(pin: String, now: Long = System.currentTimeMillis()): Boolean {
        if (isUnavailable || !hasPIN) {
            _message.value = "Parental controls could not be read. Try reopening the app."
            return false
        }
        val retryAfter = record[Field.RETRY_AFTER]?.toLongOrNull()
        if (retryAfter != null && retryAfter > now) {
            _message.value = "Too many attempts. Try again in ${(retryAfter - now + 999) / 1000} seconds."
            return false
        }
        if (!isValid(pin) || verifier(pin, record.getValue(Field.SALT)) != record[Field.VERIFIER]) {
            var failed = (record[Field.FAILED]?.toIntOrNull() ?: 0) + 1
            var lockedUntil: Long? = null
            if (failed >= Limits.ATTEMPTS) {
                failed = 0
                lockedUntil = now + Limits.COOLDOWN_MS
            }
            persist(record + (Field.FAILED to failed.toString()) - Field.RETRY_AFTER +
                (lockedUntil?.let { mapOf(Field.RETRY_AFTER to it.toString()) } ?: emptyMap()))
            _message.value = if (lockedUntil != null) "Too many attempts. Try again in a minute." else "Incorrect PIN."
            return false
        }
        persist(record + (Field.FAILED to "0") - Field.RETRY_AFTER)
        _isAuthorized.value = true
        _message.value = null
        return true
    }

    /** Sets a new PIN (when parental controls are first turned on). */
    fun setPIN(pin: String): Boolean {
        if (!isValid(pin)) {
            _message.value = "Use a four-digit PIN."
            return false
        }
        val salt = UUID.randomUUID().toString()
        persist(mapOf(Field.SALT to salt, Field.VERIFIER to verifier(pin, salt), Field.FAILED to "0"))
        _isAuthorized.value = true
        _message.value = null
        return true
    }

    fun endAuthorization() {
        _isAuthorized.value = false
        _message.value = null
    }

    fun showMessage(text: String?) {
        _message.value = text
    }

    private fun persist(updated: Map<String, String>) {
        vault.save(updated)
        record = updated
    }

    private fun verifier(pin: String, salt: String): String =
        MessageDigest.getInstance(DIGEST).digest((salt + pin).toByteArray()).joinToString("") { "%02x".format(it) }
}
