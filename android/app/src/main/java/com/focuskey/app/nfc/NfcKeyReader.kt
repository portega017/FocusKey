package com.focuskey.app.nfc

import android.app.Activity
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.os.Handler
import android.os.Looper

/** Reads FocusKey NFC tags: NDEF text records containing exactly `FOCUSKEY:TOGGLE`. */
class NfcKeyReader(private val activity: Activity) {

    enum class Availability { AVAILABLE, DISABLED, UNSUPPORTED }

    private val adapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)
    private val mainHandler = Handler(Looper.getMainLooper())

    val availability: Availability
        get() = when {
            adapter == null -> Availability.UNSUPPORTED
            !adapter.isEnabled -> Availability.DISABLED
            else -> Availability.AVAILABLE
        }

    /** Starts listening for tags while the activity is in the foreground. */
    fun start(onResult: (isValidKey: Boolean) -> Unit) {
        val adapter = adapter ?: return
        val flags = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V
        adapter.enableReaderMode(activity, { tag ->
            val valid = isValidFocusKeyTag(tag)
            mainHandler.post { onResult(valid) }
        }, flags, null)
    }

    fun stop() {
        adapter?.disableReaderMode(activity)
    }

    private fun isValidFocusKeyTag(tag: Tag): Boolean {
        val ndef = Ndef.get(tag) ?: return false
        val message: NdefMessage? = readMessage(ndef)
        return message?.records?.any { readText(it) == KEY_TEXT } ?: false
    }

    private fun readMessage(ndef: Ndef): NdefMessage? {
        return try {
            ndef.connect()
            ndef.ndefMessage ?: ndef.cachedNdefMessage
        } catch (e: Exception) {
            ndef.cachedNdefMessage
        } finally {
            runCatching { ndef.close() }
        }
    }

    /** Decodes an NDEF Well Known Text record (status byte, language code, text). */
    private fun readText(record: NdefRecord): String? {
        if (record.tnf != NdefRecord.TNF_WELL_KNOWN || !record.type.contentEquals(NdefRecord.RTD_TEXT)) {
            return null
        }
        val payload = record.payload
        if (payload.isEmpty()) return null
        val status = payload[0].toInt()
        val languageLength = status and 0x3F
        val start = 1 + languageLength
        if (payload.size < start) return null
        val charset = if (status and 0x80 != 0) Charsets.UTF_16 else Charsets.UTF_8
        return String(payload, start, payload.size - start, charset)
    }

    companion object {
        const val KEY_TEXT = "FOCUSKEY:TOGGLE"
    }
}
