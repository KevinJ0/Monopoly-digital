package com.monopoly.monopoly_banking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import net.touchcapture.qr.flutterqr.QrShared
import net.touchcapture.qr.flutterqr.QRViewFactory

class MainActivity : FlutterActivity() {
    private var bleServer: BleServer? = null
    private var bleDebugServer: BleServer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Manually register qr_code_scanner platform view factory
        try {
            flutterEngine.platformViewsController.registry.registerViewFactory(
                "net.touchcapture.qr.flutterqr/qrview",
                QRViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
            QrShared.activity = this
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to register QR platform view", e)
        }

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // BLE channel
        MethodChannel(messenger, "com.monopoly/ble")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestBlePermissions" -> {
                        result.success(requestBlePermissions())
                    }

                    "hasBleHardware" -> {
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        result.success(adapter != null)
                    }

                    "hasBlePermissions" -> {
                        result.success(hasBlePermissions())
                    }

                    "isBleEnabled" -> {
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        result.success(adapter?.isEnabled == true)
                    }

                    "openBleSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        } catch (_: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                            } catch (_: Exception) {
                                startActivity(Intent(Settings.ACTION_SETTINGS))
                            }
                        }
                        result.success(null)
                    }

                    "startBleServer" -> {
                        val serviceUuid = call.argument<String>("serviceUuid") ?: ""
                        val charUuid = call.argument<String>("charUuid") ?: ""
                        bleServer?.stop()
                        releaseWakeLock()
                        bleServer = BleServer(this, MethodChannel(messenger, "com.monopoly/ble"))
                        bleServer?.start(serviceUuid, charUuid)
                        acquireWakeLock()
                        result.success(null)
                    }

                    "stopBleServer" -> {
                        bleServer?.stop()
                        bleServer = null
                        releaseWakeLock()
                        result.success(null)
                    }

                    "bleSendNotification" -> {
                        val payload = call.argument<String>("payload") ?: ""
                        val sent = bleServer?.sendNotification(payload) == true
                        result.success(sent)
                    }

                    "bleIsClientConnected" -> {
                        val connected = bleServer?.isClientConnected() == true
                        val subscribed = bleServer?.isClientSubscribed() == true
                        result.success(mapOf("connected" to connected, "subscribed" to subscribed))
                    }

                    "bleDisconnectClient" -> {
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        result.success(bleServer?.disconnectClient(deviceId) == true)
                    }

                    "bleResetState" -> {
                        bleServer?.stop()
                        bleServer = null
                        releaseWakeLock()
                        result.success(true)
                    }

                    "bleRestartBluetooth" -> {
                        result.success(restartBluetooth())
                    }

                    "bleUnbondDevice" -> {
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        result.success(unbondDevice(deviceId))
                    }

                    "bleRefreshDeviceCache" -> {
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        result.success(refreshDeviceCache(deviceId))
                    }

                    "acquireWakeLock" -> {
                        acquireWakeLock()
                        result.success(true)
                    }

                    "releaseWakeLock" -> {
                        releaseWakeLock()
                        result.success(true)
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                })
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Error solicitando ignorar optimización", e)
                            }
                        }
                        result.success(true)
                    }

                    "keepScreenOn" -> {
                        val keepOn = call.argument<Boolean>("keepOn") ?: false
                        keepScreenOn(keepOn)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        // Canal completamente aislado para las pruebas BLE. No comparte la
        // instancia GATT ni los callbacks con el transporte del juego.
        val bleDebugChannel = MethodChannel(messenger, "com.monopoly/ble_debug")
        bleDebugChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBlePermissions" -> result.success(requestBlePermissions())
                "hasBleHardware" -> result.success(BluetoothAdapter.getDefaultAdapter() != null)
                "hasBlePermissions" -> result.success(hasBlePermissions())
                "isBleEnabled" -> result.success(BluetoothAdapter.getDefaultAdapter()?.isEnabled == true)
                "startBleServer" -> {
                    val serviceUuid = call.argument<String>("serviceUuid") ?: ""
                    val charUuid = call.argument<String>("charUuid") ?: ""
                    bleDebugServer?.stop()
                    releaseWakeLock()
                    bleDebugServer = BleServer(this, bleDebugChannel)
                    bleDebugServer?.start(serviceUuid, charUuid)
                    acquireWakeLock()
                    result.success(null)
                }
                "stopBleServer" -> {
                    bleDebugServer?.stop()
                    bleDebugServer = null
                    releaseWakeLock()
                    result.success(null)
                }
                "bleSendNotification" -> {
                    val payload = call.argument<String>("payload") ?: ""
                    result.success(bleDebugServer?.sendNotification(payload) == true)
                }
                "bleIsClientConnected" -> result.success(
                    mapOf(
                        "connected" to (bleDebugServer?.isClientConnected() == true),
                        "subscribed" to (bleDebugServer?.isClientSubscribed() == true)
                    )
                )
                "bleResetState" -> {
                    bleDebugServer?.stop()
                    bleDebugServer = null
                    releaseWakeLock()
                    result.success(true)
                }
                "bleRestartBluetooth" -> {
                    result.success(restartBluetooth())
                }

                "bleUnbondDevice" -> {
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    result.success(unbondDevice(deviceId))
                }

                "bleRefreshDeviceCache" -> {
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    result.success(refreshDeviceCache(deviceId))
                }

                "acquireWakeLock" -> {
                    acquireWakeLock()
                    result.success(true)
                }
                "releaseWakeLock" -> {
                    releaseWakeLock()
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            })
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error solicitando ignorar optimización", e)
                        }
                    }
                    result.success(true)
                }
                "keepScreenOn" -> {
                    val keepOn = call.argument<Boolean>("keepOn") ?: false
                    keepScreenOn(keepOn)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun restartBluetooth(): Boolean {
        return try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                ?: BluetoothAdapter.getDefaultAdapter()
                ?: return false
            if (adapter.isEnabled) {
                @Suppress("DEPRECATION")
                adapter.disable()
            }
            // Esperar hasta que el adaptador esté apagado (máximo 4s)
            var attempts = 0
            while (adapter.isEnabled && attempts < 20) {
                Thread.sleep(200)
                attempts++
            }
            @Suppress("DEPRECATION")
            adapter.enable()
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun getRemoteDevice(deviceId: String): BluetoothDevice? {
        return try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                ?: BluetoothAdapter.getDefaultAdapter()
            adapter?.getRemoteDevice(deviceId)
        } catch (e: Exception) {
            null
        }
    }

    private fun unbondDevice(deviceId: String): Boolean {
        return try {
            val device = getRemoteDevice(deviceId) ?: return false
            val method = device.javaClass.getMethod("removeBond")
            method.invoke(device) as Boolean
        } catch (e: Exception) {
            Log.e("MainActivity", "Error removiendo bond de $deviceId", e)
            false
        }
    }

    private fun refreshDeviceCache(deviceId: String): Boolean {
        val device = getRemoteDevice(deviceId) ?: return false
        var success = false
        val latch = java.util.concurrent.CountDownLatch(1)
        val gatt = device.connectGatt(this, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    try {
                        val refreshMethod = gatt.javaClass.getMethod("refresh")
                        success = refreshMethod.invoke(gatt) as Boolean
                        Log.d("MainActivity", "refresh() en $deviceId: $success")
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error refrescando caché GATT", e)
                    }
                    gatt.disconnect()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    gatt.close()
                    latch.countDown()
                }
            }
        })
        try {
            latch.await(4, java.util.concurrent.TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e("MainActivity", "Esperando refresh", e)
        }
        gatt?.close()
        return success
    }

    private fun blePermissions(): List<String> {
        val perms = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            perms.add(Manifest.permission.BLUETOOTH_SCAN)
            perms.add(Manifest.permission.BLUETOOTH_ADVERTISE)
            perms.add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return perms
    }

    private fun hasBlePermissions(): Boolean {
        return blePermissions().all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBlePermissions(): Boolean {
        val perms = blePermissions()
        val needed = perms.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), 1001)
            return false
        }
        return true
    }

    fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MonopolyBle::WakeLock")
                wakeLock?.setReferenceCounted(false)
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(10 * 60 * 1000L) // 10 minutos max
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error adquiriendo wake lock", e)
        }
    }

    fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error liberando wake lock", e)
        }
    }

    private fun keepScreenOn(keepOn: Boolean) {
        runOnUiThread {
            try {
                if (keepOn) {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Error cambiando keep screen on", e)
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    override fun onDestroy() {
        bleServer?.stop()
        bleServer = null
        bleDebugServer?.stop()
        bleDebugServer = null
        releaseWakeLock()
        super.onDestroy()
    }
}
