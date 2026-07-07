package com.monopoly.monopoly_banking

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

/**
 * HCE service: emula una tarjeta ISO 14443-4.
 * El banco pone un payload JSON aquí. El cliente lo lee como si fuera una tarjeta.
 *
 * Protocolo:
 *   1. SELECT AID  → responde 9000 (OK)
 *   2. GET DATA    → responde el payload JSON + 9000
 */
class HceService : HostApduService() {

    companion object {
        private const val TAG = "HceService"

        // AID de la app: F04D4F4E4F504F4C59 ("MONOPOLY" en hex con prefijo F0)
        private val SELECT_AID_HEADER = byteArrayOf(
            0x00.toByte(), 0xA4.toByte(), 0x04.toByte(), 0x00.toByte()
        )
        private val GET_DATA_CMD = byteArrayOf(
            0x00.toByte(), 0xCA.toByte(), 0x00.toByte(), 0x00.toByte()
        )

        private val OK      = byteArrayOf(0x90.toByte(), 0x00.toByte())
        private val UNKNOWN = byteArrayOf(0x6D.toByte(), 0x00.toByte())
        private val NO_DATA = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        // Payload compartido entre HceService y MainActivity
        @Volatile var pendingPayload: ByteArray? = null
    }

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        Log.d(TAG, "APDU recibido: ${commandApdu.toHex()}")

        return when {
            commandApdu.startsWith(SELECT_AID_HEADER) -> {
                Log.d(TAG, "SELECT AID → OK")
                OK
            }
            commandApdu.startsWith(GET_DATA_CMD) -> {
                val payload = pendingPayload
                if (payload == null) {
                    Log.d(TAG, "GET DATA → sin datos")
                    NO_DATA
                } else {
                    Log.d(TAG, "GET DATA → enviando ${payload.size} bytes")
                    // Codifica longitud como 2 bytes + datos + OK
                    val response = ByteArray(2 + payload.size + 2)
                    response[0] = ((payload.size shr 8) and 0xFF).toByte()
                    response[1] = (payload.size and 0xFF).toByte()
                    System.arraycopy(payload, 0, response, 2, payload.size)
                    response[response.size - 2] = 0x90.toByte()
                    response[response.size - 1] = 0x00.toByte()
                    response
                }
            }
            else -> {
                Log.d(TAG, "APDU desconocido: ${commandApdu.toHex()}")
                UNKNOWN
            }
        }
    }

    override fun onDeactivated(reason: Int) {
        Log.d(TAG, "HCE desactivado: reason=$reason")
    }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
        if (this.size < prefix.size) return false
        return prefix.indices.all { this[it] == prefix[it] }
    }

    private fun ByteArray.toHex(): String =
        joinToString(":") { "%02X".format(it) }
}
