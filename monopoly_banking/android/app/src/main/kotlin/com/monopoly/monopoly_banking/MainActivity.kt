package com.monopoly.monopoly_banking

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.bluetooth.BluetoothAdapter
import android.nfc.NfcAdapter
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bleServer: BleServer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // NFC channel
        MethodChannel(messenger, "com.monopoly/nfc")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasNfcHardware" -> {
                        val adapter = NfcAdapter.getDefaultAdapter(this)
                        result.success(adapter != null)
                    }

                    "isNfcEnabled" -> {
                        val adapter = NfcAdapter.getDefaultAdapter(this)
                        result.success(adapter?.isEnabled == true)
                    }

                    "openNfcSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                        } catch (_: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                            } catch (_: Exception) {
                                startActivity(Intent(Settings.ACTION_SETTINGS))
                            }
                        }
                        result.success(null)
                    }

                    "hceStart" -> {
                        val jsonPayload = call.argument<String>("payload") ?: ""
                        HceService.pendingPayload = jsonPayload.toByteArray(Charsets.UTF_8)
                        result.success(null)
                    }

                    "hceStop" -> {
                        HceService.pendingPayload = null
                        result.success(null)
                    }

                    "hceRead" -> {
                        result.notImplemented()
                    }

                    else -> result.notImplemented()
                }
            }

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
                        bleServer = BleServer(this, MethodChannel(messenger, "com.monopoly/ble"))
                        bleServer?.start(serviceUuid, charUuid)
                        result.success(null)
                    }

                    "stopBleServer" -> {
                        bleServer?.stop()
                        bleServer = null
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

                    else -> result.notImplemented()
                }
            }
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

    override fun onDestroy() {
        bleServer?.stop()
        bleServer = null
        super.onDestroy()
    }
}
