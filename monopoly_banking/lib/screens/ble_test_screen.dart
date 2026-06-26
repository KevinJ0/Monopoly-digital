import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({super.key});

  @override
  State<BleTestScreen> createState() => _BleTestScreenState();
}

enum _BleAvailability { enabled, disabled, unsupported }

class _BleTestScreenState extends State<BleTestScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.monopoly/ble');

  static const String _serviceUuid = '12345678-0000-1000-8000-00805f9b34fb';
  static const String _charUuid = '12345678-0001-1000-8000-00805f9b34fb';

  final _ble = FlutterReactiveBle();

  _BleAvailability _availability = _BleAvailability.unsupported;
  bool _serverActive = false;
  bool _scanning = false;
  bool _connected = false;
  String? _connectedDeviceId;
  String? _connectedDeviceName;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectSub;
  Timer? _scanTimeout;

  final List<_LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopServer();
    _stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBle();
    }
  }

  Future<void> _checkBle() async {
    _addLog('Verificando hardware Bluetooth...', _LogLevel.info);
    try {
      final hasHardware =
          await _channel.invokeMethod<bool>('hasBleHardware') ?? false;
      if (!hasHardware) {
        setState(() => _availability = _BleAvailability.unsupported);
        _addLog('BLUETOOTH: NO SOPORTADO en este dispositivo', _LogLevel.error);
        return;
      }
      final isEnabled =
          await _channel.invokeMethod<bool>('isBleEnabled') ?? false;
      setState(() => _availability =
          isEnabled ? _BleAvailability.enabled : _BleAvailability.disabled);
      _addLog(
        isEnabled
            ? 'BLUETOOTH: ACTIVO y listo'
            : 'BLUETOOTH: DESACTIVADO (hardware presente)',
        isEnabled ? _LogLevel.ok : _LogLevel.warn,
      );
    } catch (e) {
      _addLog('Error al verificar Bluetooth: $e', _LogLevel.error);
    }
  }

  void _addLog(String msg, _LogLevel level) {
    final now = TimeOfDay.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, _LogEntry(ts: ts, msg: msg, level: level));
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  String _availabilityLabel(_BleAvailability a) {
    switch (a) {
      case _BleAvailability.enabled:
        return 'ACTIVO';
      case _BleAvailability.disabled:
        return 'DESACTIVADO';
      case _BleAvailability.unsupported:
        return 'NO SOPORTADO';
    }
  }

  // ── Servidor BLE ──────────────────────────────────────────────────

  Future<void> _startServer() async {
    if (_availability != _BleAvailability.enabled) {
      _addLog('Bluetooth no está activo — actívalo primero', _LogLevel.error);
      return;
    }
    if (_serverActive) {
      _addLog('El servidor BLE ya está activo', _LogLevel.warn);
      return;
    }
    setState(() => _serverActive = true);
    _addLog('Iniciando servidor BLE...', _LogLevel.info);

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'bleDataReceived') {
        try {
          final jsonStr = call.arguments as String;
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          _addLog('━━━ DATOS RECIBIDOS ━━━', _LogLevel.ok);
          _addLog('Payload: $data', _LogLevel.ok);
          _addLog('━━━━━━━━━━━━━━━━━━━━━━', _LogLevel.ok);
        } catch (_) {}
      }
      return null;
    });

    try {
      await _channel.invokeMethod('startBleServer', {
        'serviceUuid': _serviceUuid,
        'charUuid': _charUuid,
      });
      _addLog('Servidor BLE ACTIVO — esperando conexiones...', _LogLevel.ok);
      _addLog('UUID Servicio: $_serviceUuid', _LogLevel.info);
      _addLog('UUID Característica: $_charUuid', _LogLevel.info);
    } catch (e, s) {
      _addLog('Error al iniciar servidor BLE: $e', _LogLevel.error);
      if (mounted) context.showFriendlyError(e, s);
      setState(() => _serverActive = false);
    }
  }

  Future<void> _stopServer() async {
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod('stopBleServer');
    } catch (_) {}
    setState(() => _serverActive = false);
    _addLog('Servidor BLE detenido', _LogLevel.info);
  }

  // ── Escáner Cliente BLE ───────────────────────────────────────────

  Future<void> _startScan() async {
    if (_availability != _BleAvailability.enabled) {
      _addLog('Bluetooth no está activo', _LogLevel.error);
      return;
    }
    if (_scanning) {
      _addLog('Ya hay un escaneo activo', _LogLevel.warn);
      return;
    }
    setState(() => _scanning = true);
    _addLog('Escaneando dispositivos BLE...', _LogLevel.info);

    _scanTimeout = Timer(const Duration(seconds: 15), () {
      _addLog('Escaneo terminado por tiempo (15s)', _LogLevel.warn);
      _stopScan();
    });

    _scanSub = _ble.scanForDevices(
      withServices: [Uuid.parse(_serviceUuid)],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (!mounted) return;
      _addLog('Dispositivo encontrado: ${device.name} [${device.id}]',
          _LogLevel.ok);
      _connectedDeviceId = device.id;
      _connectedDeviceName = device.name;
      _addLog('Conectando a ${device.name}...', _LogLevel.info);
      _connectToDevice(device.id);
    }, onError: (e) {
      _addLog('Error de escaneo: $e', _LogLevel.error);
    });
  }

  void _connectToDevice(String deviceId) {
    _scanTimeout?.cancel();
    _scanSub?.cancel();
    _scanSub = null;

    _connectSub = _ble.connectToDevice(
      id: deviceId,
      servicesWithCharacteristicsToDiscover: {
        Uuid.parse(_serviceUuid): [Uuid.parse(_charUuid)],
      },
    ).listen((state) {
      if (!mounted) return;
      switch (state.connectionState) {
        case DeviceConnectionState.connecting:
          _addLog('Conectando...', _LogLevel.info);
        case DeviceConnectionState.connected:
          setState(() => _connected = true);
          _addLog('¡CONECTADO a $_connectedDeviceName!', _LogLevel.ok);
          _sendTestPayload();
        case DeviceConnectionState.disconnecting:
          _addLog('Desconectando...', _LogLevel.info);
        case DeviceConnectionState.disconnected:
          if (_connected) {
            _addLog('Dispositivo desconectado', _LogLevel.warn);
          }
          setState(() {
            _connected = false;
            _connectedDeviceId = null;
          });
      }
    }, onError: (e) {
      _addLog('Error de conexión: $e', _LogLevel.error);
      _stopScan();
    });
  }

  Future<void> _sendTestPayload() async {
    if (_connectedDeviceId == null) return;

    final payload = {
      'type': 'ble_test',
      'message': 'Hola desde BLE Test!',
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_charUuid),
      deviceId: _connectedDeviceId!,
    );

    try {
      await _ble.writeCharacteristicWithResponse(
        characteristic,
        value: utf8.encode(jsonEncode(payload)),
      );
      _addLog('Payload enviado: $payload', _LogLevel.ok);
    } catch (e) {
      _addLog('Error al enviar payload: $e', _LogLevel.error);
    }
  }

  Future<void> _stopScan() async {
    _scanTimeout?.cancel();
    _scanTimeout = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await _connectSub?.cancel();
    _connectSub = null;
    setState(() {
      _scanning = false;
    });
    _addLog('Escaneo detenido', _LogLevel.info);
  }

  Future<void> _disconnect() async {
    _scanTimeout?.cancel();
    _scanTimeout = null;
    _connectSub?.cancel();
    _connectSub = null;
    _scanSub?.cancel();
    _scanSub = null;
    setState(() {
      _connected = false;
      _connectedDeviceId = null;
      _connectedDeviceName = null;
    });
    _addLog('Desconectado manualmente', _LogLevel.info);
  }

  Future<void> _openBleSettings() async {
    try {
      await _channel.invokeMethod<void>('openBleSettings');
      _addLog('Abriendo ajustes de Bluetooth del sistema...', _LogLevel.info);
    } catch (e, s) {
      _addLog('No se pudo abrir ajustes: $e', _LogLevel.error);
      if (mounted) context.showFriendlyError(e, s);
    }
  }

  Color _levelColor(_LogLevel level) {
    switch (level) {
      case _LogLevel.ok:
        return kGreen;
      case _LogLevel.info:
        return kTextSecondary;
      case _LogLevel.warn:
        return kGold;
      case _LogLevel.error:
        return kRed;
    }
  }

  IconData _levelIcon(_LogLevel level) {
    switch (level) {
      case _LogLevel.ok:
        return Icons.check_circle_outline_rounded;
      case _LogLevel.info:
        return Icons.info_outline_rounded;
      case _LogLevel.warn:
        return Icons.warning_amber_rounded;
      case _LogLevel.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = _availability == _BleAvailability.enabled;
    final isUnsupported = _availability == _BleAvailability.unsupported;

    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kTextSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'BLE Debug',
          style: TextStyle(
              color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
            tooltip: 'Re-verificar estado Bluetooth',
            onPressed: _checkBle,
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: kTextSecondary),
            tooltip: 'Copiar todos los logs',
            onPressed: () {
              if (_logs.isEmpty) return;
              final text =
                  _logs.reversed.map((e) => '[${e.ts}] ${e.msg}').join('\n');
              Clipboard.setData(ClipboardData(text: text));
              NotificationService().show('Logs copiados al portapapeles',
                  duration: const Duration(seconds: 2));
            },
          ),
          IconButton(
            icon:
                const Icon(Icons.delete_outline_rounded, color: kTextSecondary),
            tooltip: 'Limpiar logs',
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Estado Bluetooth ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isEnabled
                    ? kGreen.withValues(alpha: 0.4)
                    : isUnsupported
                        ? kRed.withValues(alpha: 0.4)
                        : kGold.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bluetooth_rounded,
                      color: isEnabled
                          ? kGreen
                          : isUnsupported
                              ? kRed
                              : kGold,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estado del Bluetooth',
                            style: TextStyle(
                              color: kTextSecondary,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _availabilityLabel(_availability),
                            style: TextStyle(
                              color: isEnabled
                                  ? kGreen
                                  : isUnsupported
                                      ? kRed
                                      : kGold,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled
                            ? kGreen
                            : isUnsupported
                                ? kRed
                                : kGold,
                        boxShadow: [
                          BoxShadow(
                            color: (isEnabled
                                    ? kGreen
                                    : isUnsupported
                                        ? kRed
                                        : kGold)
                                .withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isEnabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isUnsupported ? null : _openBleSettings,
                      icon: const Icon(Icons.settings_rounded, size: 16),
                      label: Text(isUnsupported
                          ? 'Hardware no disponible'
                          : 'Abrir ajustes para activar Bluetooth'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGold,
                        side: BorderSide(color: kGold.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Modo Servidor BLE ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _serverActive
                        ? null
                        : (isEnabled ? _startServer : null),
                    icon: _serverActive
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.bluetooth_searching_rounded,
                            size: 18),
                    label: Text(_serverActive
                        ? 'Servidor activo...'
                        : 'Iniciar Servidor BLE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _serverActive
                          ? Colors.blue.shade800
                          : (isEnabled
                              ? Colors.blue.shade600
                              : Colors.grey.shade800),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _serverActive ? _stopServer : null,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Detener'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _serverActive ? kRed : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Modo Cliente BLE ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanning
                        ? null
                        : (isEnabled && !_serverActive ? _startScan : null),
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.search_rounded, size: 18),
                    label: Text(
                        _scanning ? 'Escaneando...' : 'Escanear dispositivos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isEnabled ? kGreen : Colors.grey.shade800,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _connected
                        ? _disconnect
                        : (_scanning ? _stopScan : null),
                    icon: Icon(
                        _connected
                            ? Icons.bluetooth_disabled_rounded
                            : Icons.stop_circle_outlined,
                        size: 18),
                    label: Text(_connected ? 'Desconectar' : 'Detener'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_scanning || _connected)
                          ? kRed
                          : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded,
                    color: kTextSecondary, size: 14),
                const SizedBox(width: 6),
                const Text(
                  'LOG EN TIEMPO REAL',
                  style: TextStyle(
                      color: kTextSecondary,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${_logs.length} entradas',
                  style: const TextStyle(color: kTextSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Lista de logs ────────────────────────────────────────────
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF060B14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bluetooth_rounded,
                              color: Colors.white12, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Inicia el servidor BLE en un\ndispositivo y escanea desde otro',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white24, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      reverse: false,
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final e = _logs[i];
                        return GestureDetector(
                          onLongPress: () {
                            Clipboard.setData(
                                ClipboardData(text: '[${e.ts}] ${e.msg}'));
                            NotificationService().show('Línea copiada',
                                duration: const Duration(seconds: 1));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.ts,
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(_levelIcon(e.level),
                                    color: _levelColor(e.level), size: 13),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    e.msg,
                                    style: TextStyle(
                                      color: _levelColor(e.level),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LogEntry {
  final String ts;
  final String msg;
  final _LogLevel level;
  _LogEntry({required this.ts, required this.msg, required this.level});
}

enum _LogLevel { ok, info, warn, error }
