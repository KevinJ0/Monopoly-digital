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

    @Volatile
    private var isStarted = false
    @Volatile
    private var isStarting = false
    @Volatile
    private var isAdvertisingActive = false

    private val connectedDevices = mutableSetOf<android.bluetooth.BluetoothDevice>()
    private val subscribedDevices = mutableSetOf<android.bluetooth.BluetoothDevice>()
    private val notificationsInFlight = mutableMapOf<android.bluetooth.BluetoothDevice, Long>()

    private var advertisingWatchdog: Runnable? = null

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: android.bluetooth.BluetoothGattService) {
            Log.d(TAG, "onServiceAdded: ${service.uuid} status=$status")
            isStarting = false
            if (status == BluetoothGatt.GATT_SUCCESS) {
                isStarted = true
                mainHandler.post { startAdvertising() }
            } else {
                isStarted = false
                mainHandler.post {
                    channel.invokeMethod(
                        "bleServerAdvertisingFailed",
                        mapOf("errorCode" to (-1000 - status))
                    )
                }
            }
        }

        override fun onConnectionStateChange(device: android.bluetooth.BluetoothDevice, status: Int, newState: Int) {
            Log.d(TAG, "onConnectionStateChange: ${device.address} status=$status newState=$newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                synchronized(connectedDevices) {
                    connectedDevices.add(device)
                }
                mainHandler.post {
                    channel.invokeMethod("bleClientConnected", deviceInfo(device))
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                synchronized(connectedDevices) {
                    connectedDevices.remove(device)
                    subscribedDevices.remove(device)
                }
                notificationsInFlight.remove(device)
                mainHandler.post {
                    channel.invokeMethod("bleClientDisconnected", deviceInfo(device, status))
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
                    synchronized(connectedDevices) { subscribedDevices.add(device) }
                    Log.d(TAG, "Cliente ${device.address} suscrito a notificaciones")
                    mainHandler.post {
                        channel.invokeMethod("bleClientSubscribed", deviceInfo(device))
                    }
                } else {
                    synchronized(connectedDevices) { subscribedDevices.remove(device) }
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
        if (isStarting || isStarted) {
            Log.d(TAG, "start: servidor ya iniciado o iniciando, reiniciando...")
            stop()
        }
        serviceUuid = UUID.fromString(serviceUuidStr)
        charUuid = UUID.fromString(charUuidStr)
        isStarting = true
        isStarted = false

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
        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (bleAdvertiser == null) {
            Log.e(TAG, "BLE advertiser no disponible")
            channel.invokeMethod("bleServerAdvertisingFailed", mapOf("errorCode" to -3))
            return
        }

        service.addCharacteristic(notifyCharacteristic)
        if (gattServer?.addService(service) != true) {
            isStarting = false
            isStarted = false
            Log.e(TAG, "No se pudo agregar el servicio GATT")
            channel.invokeMethod("bleServerAdvertisingFailed", mapOf("errorCode" to -4))
        }
    }

    private fun startAdvertising() {
        val uuid = serviceUuid ?: return
        val advertiser = bleAdvertiser ?: return
        if (advertiseCallback != null) {
            Log.w(TAG, "startAdvertising: ya hay un callback activo")
            return
        }
        if (!isStarted) {
            Log.w(TAG, "startAdvertising: servidor no está marcado como iniciado")
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(uuid))
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                Log.d(TAG, "BLE advertising iniciado exitosamente")
                isAdvertisingActive = true
                startAdvertisingWatchdog()
                channel.invokeMethod("bleServerAdvertisingStarted", null)
            }

            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "BLE advertising falló: errorCode=$errorCode")
                isAdvertisingActive = false
                channel.invokeMethod(
                    "bleServerAdvertisingFailed",
                    mapOf("errorCode" to errorCode)
                )
            }
        }

        advertiser.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    private fun startAdvertisingWatchdog() {
        stopAdvertisingWatchdog()
        val watchdog = object : Runnable {
            override fun run() {
                if (!isStarted) return
                if (!isAdvertisingActive && advertiseCallback == null && bleAdvertiser != null) {
                    Log.w(TAG, "Watchdog: advertising se detuvo inesperadamente, reiniciando...")
                    mainHandler.post { startAdvertising() }
                }
                mainHandler.postDelayed(this, 5000)
            }
        }
        advertisingWatchdog = watchdog
        mainHandler.postDelayed(watchdog, 5000)
    }

    private fun stopAdvertisingWatchdog() {
        advertisingWatchdog?.let { mainHandler.removeCallbacks(it) }
        advertisingWatchdog = null
    }

    fun sendNotification(jsonPayload: String): Boolean {
        val char = notifyCharacteristic ?: return false
        val bytes = jsonPayload.toByteArray(Charsets.UTF_8)

        if (bytes.size > 512) {
            Log.e(TAG, "Payload demasiado grande: ${bytes.size} bytes (max 512)")
            return false
        }

        // Limpiar notificaciones atascadas (> 3s sin onNotificationSent)
        val now = System.currentTimeMillis()
        val staleKeys = mutableListOf<android.bluetooth.BluetoothDevice>()
        for ((device, sendTime) in notificationsInFlight) {
            if (now - sendTime > 3000) {
                staleKeys.add(device)
                Log.w(TAG, "Notificación atascada para ${device.address} (>3s), liberando canal")
            }
        }
        for (d in staleKeys) notificationsInFlight.remove(d)

        var sent = false
        // Copiar para evitar ConcurrentModificationException si se desconecta un dispositivo
        val targets = subscribedDevices.toList()
        for (device in targets) {
            if (device in notificationsInFlight) {
                if (staleKeys.contains(device)) {
                    // Ya fue liberado, continuar
                } else {
                    Log.w(TAG, "Notificación anterior aún pendiente para ${device.address}")
                    continue
                }
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
                    notificationsInFlight[device] = now
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

    fun isClientConnected(): Boolean = synchronized(connectedDevices) { connectedDevices.isNotEmpty() }
    fun isClientSubscribed(): Boolean = synchronized(subscribedDevices) { subscribedDevices.isNotEmpty() }

    fun disconnectClient(deviceId: String): Boolean {
        val device = synchronized(connectedDevices) {
            connectedDevices.firstOrNull { it.address == deviceId }
                ?: subscribedDevices.firstOrNull { it.address == deviceId }
        } ?: return false
        synchronized(connectedDevices) {
            connectedDevices.remove(device)
            subscribedDevices.remove(device)
        }
        notificationsInFlight.remove(device)
        return try {
            gattServer?.cancelConnection(device)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error desconectando cliente $deviceId", e)
            false
        }
    }

    fun disconnectAllClients() {
        val devices = synchronized(connectedDevices) {
            val all = connectedDevices.toList()
            connectedDevices.clear()
            subscribedDevices.clear()
            notificationsInFlight.clear()
            all
        }
        for (device in devices) {
            try {
                gattServer?.cancelConnection(device)
            } catch (e: Exception) {
                Log.e(TAG, "Error desconectando cliente ${device.address}", e)
            }
        }
    }

    private fun deviceInfo(device: android.bluetooth.BluetoothDevice, disconnectStatus: Int? = null): Map<String, String> {
        val info = mutableMapOf(
            "deviceId" to device.address,
            "deviceName" to (device.name ?: "")
        )
        disconnectStatus?.let { info["status"] = it.toString() }
        return info
    }

    fun stop() {
        Log.d(TAG, "stop")
        isStarted = false
        isStarting = false
        isAdvertisingActive = false
        stopAdvertisingWatchdog()

        val callback = advertiseCallback
        advertiseCallback = null
        callback?.let {
            try {
                bleAdvertiser?.stopAdvertising(it)
            } catch (_: Exception) {
            }
        }
        bleAdvertiser = null

        val devices = synchronized(connectedDevices) {
            val all = connectedDevices.toList()
            connectedDevices.clear()
            subscribedDevices.clear()
            notificationsInFlight.clear()
            all
        }
        for (device in devices) {
            try {
                gattServer?.cancelConnection(device)
            } catch (_: Exception) {
            }
        }

        try {
            gattServer?.clearServices()
        } catch (_: Exception) {
        }
        try {
            gattServer?.close()
        } catch (_: Exception) {
        }
        gattServer = null
        notifyCharacteristic = null
        serviceUuid = null
        charUuid = null

        bluetoothAdapter = null
        bluetoothManager = null
    }
}
