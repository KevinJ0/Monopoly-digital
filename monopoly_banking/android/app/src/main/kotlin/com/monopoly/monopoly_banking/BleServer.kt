package com.monopoly.monopoly_banking

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.Arrays
import java.util.UUID

class BleServer(private val context: Context, private val channel: MethodChannel) {
    companion object {
        private const val TAG = "BleServer"
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null

    private var serviceUuid: UUID? = null
    private var charUuid: UUID? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val connectedDevices = mutableSetOf<android.bluetooth.BluetoothDevice>()
    private val subscribedDevices = mutableSetOf<android.bluetooth.BluetoothDevice>()
    private val notificationsInFlight = mutableSetOf<android.bluetooth.BluetoothDevice>()

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: android.bluetooth.BluetoothDevice, status: Int, newState: Int) {
            Log.d(TAG, "onConnectionStateChange: ${device.address} status=$status newState=$newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevices.add(device)
                mainHandler.post {
                    channel.invokeMethod("bleClientConnected", deviceInfo(device))
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedDevices.remove(device)
                subscribedDevices.remove(device)
                notificationsInFlight.remove(device)
                mainHandler.post {
                    channel.invokeMethod("bleClientDisconnected", deviceInfo(device))
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: android.bluetooth.BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            Log.d(TAG, "onCharacteristicWriteRequest: ${device.address} ${value.size} bytes")
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
            val jsonStr = String(value, Charsets.UTF_8)
            mainHandler.post {
                channel.invokeMethod("bleDataReceived", mapOf(
                    "deviceId" to device.address,
                    "deviceName" to (device.name ?: ""),
                    "payload" to jsonStr
                ))
            }
        }

        override fun onDescriptorWriteRequest(
            device: android.bluetooth.BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            Log.d(TAG, "onDescriptorWriteRequest: ${device.address} uuid=${descriptor.uuid}")
            if (descriptor.uuid == CCCD_UUID) {
                val enabled = Arrays.equals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE, value) ||
                    Arrays.equals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE, value)
                if (enabled) {
                    subscribedDevices.add(device)
                    Log.d(TAG, "Cliente ${device.address} suscrito a notificaciones")
                    mainHandler.post {
                        channel.invokeMethod("bleClientSubscribed", deviceInfo(device))
                    }
                } else {
                    subscribedDevices.remove(device)
                    mainHandler.post {
                        channel.invokeMethod("bleClientUnsubscribed", deviceInfo(device))
                    }
                    Log.d(TAG, "Cliente ${device.address} canceló suscripción")
                }
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                }
            } else {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        override fun onNotificationSent(
            device: android.bluetooth.BluetoothDevice,
            status: Int
        ) {
            Log.d(TAG, "onNotificationSent: ${device.address} status=$status")
            notificationsInFlight.remove(device)
        }
    }

    fun start(serviceUuidStr: String, charUuidStr: String) {
        Log.d(TAG, "start: service=$serviceUuidStr char=$charUuidStr")
        serviceUuid = UUID.fromString(serviceUuidStr)
        charUuid = UUID.fromString(charUuidStr)
        stop()

        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth no soportado")
            channel.invokeMethod("bleServerAdvertisingFailed", mapOf("errorCode" to -1))
            return
        }

        if (!bluetoothAdapter!!.isEnabled) {
            Log.e(TAG, "Bluetooth desactivado")
            channel.invokeMethod("bleServerAdvertisingFailed", mapOf("errorCode" to -2))
            return
        }

        gattServer = bluetoothManager?.openGattServer(context, gattServerCallback)

        notifyCharacteristic = BluetoothGattCharacteristic(
            charUuid,
            BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE or
                BluetoothGattCharacteristic.PERMISSION_READ
        )
        notifyCharacteristic!!.value = byteArrayOf(0)

        val cccd = BluetoothGattDescriptor(
            CCCD_UUID,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        notifyCharacteristic!!.addDescriptor(cccd)

        val service = android.bluetooth.BluetoothGattService(
            serviceUuid,
            android.bluetooth.BluetoothGattService.SERVICE_TYPE_PRIMARY
        )
        service.addCharacteristic(notifyCharacteristic)
        gattServer?.addService(service)

        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (bleAdvertiser == null) {
            Log.e(TAG, "BLE advertiser no disponible")
            channel.invokeMethod("bleServerAdvertisingFailed", mapOf("errorCode" to -3))
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(serviceUuid))
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                Log.d(TAG, "BLE advertising iniciado exitosamente")
                channel.invokeMethod("bleServerAdvertisingStarted", null)
            }

            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "BLE advertising falló: errorCode=$errorCode")
                channel.invokeMethod(
                    "bleServerAdvertisingFailed",
                    mapOf("errorCode" to errorCode)
                )
            }
        }

        // addService() termina de forma asíncrona. Darle tiempo a Android para
        // publicar el servicio evita que un cliente se conecte y descubra un
        // servidor GATT todavía vacío.
        mainHandler.postDelayed({
            if (gattServer != null) {
                bleAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
            }
        }, 350)
    }

    fun sendNotification(jsonPayload: String): Boolean {
        val char = notifyCharacteristic ?: return false
        val bytes = jsonPayload.toByteArray(Charsets.UTF_8)

        if (bytes.size > 512) {
            Log.e(TAG, "Payload demasiado grande: ${bytes.size} bytes (max 512)")
            return false
        }

        var sent = false
        for (device in subscribedDevices) {
            if (device in notificationsInFlight) {
                Log.w(TAG, "Notificación anterior aún pendiente para ${device.address}")
                continue
            }
            try {
                val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gattServer?.notifyCharacteristicChanged(device, char, false, bytes) ==
                        BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    char.value = bytes
                    @Suppress("DEPRECATION")
                    gattServer?.notifyCharacteristicChanged(device, char, false) == true
                }
                if (result) {
                    notificationsInFlight.add(device)
                    Log.d(TAG, "Notificación enviada a ${device.address}")
                    sent = true
                } else {
                    Log.w(TAG, "Fallo al notificar a ${device.address}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error notificando a ${device.address}: $e")
            }
        }
        return sent
    }

    fun isClientConnected(): Boolean = connectedDevices.isNotEmpty()
    fun isClientSubscribed(): Boolean = subscribedDevices.isNotEmpty()

    fun disconnectClient(deviceId: String): Boolean {
        val device = connectedDevices.firstOrNull { it.address == deviceId }
            ?: subscribedDevices.firstOrNull { it.address == deviceId }
            ?: return false
        connectedDevices.remove(device)
        subscribedDevices.remove(device)
        notificationsInFlight.remove(device)
        return try {
            gattServer?.cancelConnection(device)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error desconectando cliente $deviceId", e)
            false
        }
    }

    private fun deviceInfo(device: android.bluetooth.BluetoothDevice): Map<String, String> {
        return mapOf(
            "deviceId" to device.address,
            "deviceName" to (device.name ?: "")
        )
    }

    fun stop() {
        Log.d(TAG, "stop")
        try {
            advertiseCallback?.let { bleAdvertiser?.stopAdvertising(it) }
        } catch (_: Exception) {}
        advertiseCallback = null
        bleAdvertiser = null

        for (device in connectedDevices) {
            try {
                gattServer?.cancelConnection(device)
            } catch (_: Exception) {}
        }
        connectedDevices.clear()
        subscribedDevices.clear()
        notificationsInFlight.clear()

        try {
            gattServer?.clearServices()
            gattServer?.close()
        } catch (_: Exception) {}
        gattServer = null
        notifyCharacteristic = null

        bluetoothAdapter = null
        bluetoothManager = null
    }
}
