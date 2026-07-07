import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/ble_diagnostic_logger.dart';

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({super.key, this.onOpenGame});

  final VoidCallback? onOpenGame;

  @override
  State<BleTestScreen> createState() => _BleTestScreenState();
}

class _BleTestScreenState extends State<BleTestScreen> {
  static const _channel = MethodChannel('com.monopoly/ble_debug');

  // UUID exclusivos de BLE Debug. No se utilizan en ninguna pantalla del juego.
  static const _serviceUuid = '7d2ea928-9c87-4e16-a0f6-b1e000000001';
  static const _characteristicUuid = '7d2ea928-9c87-4e16-a0f6-b1e000000002';

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final TextEditingController _messageController = TextEditingController();
  final List<String> _logs = <String>[];

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  Timer? _keepAliveTimer;
  DateTime? _lastPongReceived;
  int _pongMissedCount = 0;

  bool _bluetoothReady = false;
  bool _serverStarting = false;
  bool _serverActive = false;
  bool _serverClientConnected = false;
  bool _serverClientSubscribed = false;
  bool _scanning = false;
  bool _connecting = false;
  bool _clientReady = false;
  String? _deviceId;
  String _deviceName = '';

  Uuid get _service => Uuid.parse(_serviceUuid);
  Uuid get _characteristic => Uuid.parse(_characteristicUuid);

  @override
  void initState() {
    super.initState();
    BleDiagnosticLogger.instance.logEvent('LIFECYCLE', 'BleTestScreen.initState');
    _channel.setMethodCallHandler(_onNativeEvent);
    _initialize();
  }

  Future<void> _initialize() async {
    await BleDiagnosticLogger.instance.clear();
    BleDiagnosticLogger.instance.logEvent('INIT', 'BleTestScreen.initialize');
    _log('Nueva sesión BLE Debug aislada');
    _log('Servicio: $_serviceUuid');
    try {
      var permissions =
          await _channel.invokeMethod<bool>('hasBlePermissions') ?? false;
      if (!permissions) {
        permissions =
            await _channel.invokeMethod<bool>('requestBlePermissions') ?? false;
      }
      final hardware =
          await _channel.invokeMethod<bool>('hasBleHardware') ?? false;
      final enabled =
          await _channel.invokeMethod<bool>('isBleEnabled') ?? false;
      if (!mounted) return;
      setState(() => _bluetoothReady = hardware && enabled && permissions);
      _log('Hardware=$hardware, encendido=$enabled, permisos=$permissions');
      if (!permissions) {
        _log('Concede los permisos y vuelve a abrir BLE Debug');
      }
    } catch (error, stack) {
      _recordError('No se pudo preparar Bluetooth', error, stack);
    }
  }

  Future<dynamic> _onNativeEvent(MethodCall call) async {
    _log('NATIVO ${call.method}: ${call.arguments ?? ''}');
    _audit('native_${call.method}', params: _safeArgs(call.arguments));
    if (!mounted) return null;
    switch (call.method) {
      case 'bleServerAdvertisingStarted':
        setState(() {
          _serverStarting = false;
          _serverActive = true;
        });
      case 'bleServerAdvertisingFailed':
        setState(() {
          _serverStarting = false;
          _serverActive = false;
        });
      case 'bleClientConnected':
        setState(() => _serverClientConnected = true);
      case 'bleClientSubscribed':
        setState(() {
          _serverClientConnected = true;
          _serverClientSubscribed = true;
        });
      case 'bleClientUnsubscribed':
        setState(() => _serverClientSubscribed = false);
      case 'bleClientDisconnected':
        final status = call.arguments is Map ? call.arguments['status']?.toString() : null;
        _log('Jugador desconectado${status != null ? ' (status=$status)' : ''}');
        setState(() {
          _serverClientConnected = false;
          _serverClientSubscribed = false;
        });
      case 'bleDataReceived':
        final arguments = call.arguments;
        final text = arguments is Map
            ? (arguments['payload']?.toString() ?? '')
            : arguments?.toString() ?? '';
        if (text == '{"type":"ping"}') {
          _audit('received_ping');
          final sent = await _channel.invokeMethod<bool>('bleSendNotification', {
            'payload': '{"type":"pong"}',
          }) ?? false;
          if (!sent) {
            _log('Pong NO enviado - canal bloqueado');
          }
          return null;
        }
        _log('RECIBIDO DEL JUGADOR: $text');
    }
    return null;
  }

  Map<String, dynamic> _safeArgs(dynamic arguments) {
    if (arguments is Map) {
      return arguments.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
    }
    if (arguments != null) {
      return {'value': arguments.toString()};
    }
    return const {};
  }

  Future<void> _startServer() async {
    _audit('tap_start_server');
    await _fullStop();
    await _checkBatteryOptimization();
    if (!mounted) return;
    setState(() {
      _serverStarting = true;
      _serverActive = false;
      _serverClientConnected = false;
      _serverClientSubscribed = false;
    });
    _log('Iniciando servidor GATT aislado...');
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'keepOn': true});
      await _channel.invokeMethod<void>('startBleServer', {
        'serviceUuid': _serviceUuid,
        'charUuid': _characteristicUuid,
      });
    } catch (error, stack) {
      _recordError('No se pudo iniciar el servidor', error, stack);
      if (mounted) setState(() => _serverStarting = false);
    }
  }

  Future<void> _stopServer() async {
    _audit('tap_stop_server');
    try {
      await _channel.invokeMethod<void>('stopBleServer');
      await _channel.invokeMethod<void>('keepScreenOn', {'keepOn': false});
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _serverStarting = false;
      _serverActive = false;
      _serverClientConnected = false;
      _serverClientSubscribed = false;
    });
    _log('Servidor detenido');
  }

  Future<void> _scanAndConnect() async {
    _audit('tap_scan_and_connect');
    await _fullStop();
    if (!mounted) return;
    setState(() => _scanning = true);
    _log('Buscando exclusivamente el servidor BLE Debug...');

    final completer = Completer<DiscoveredDevice>();
    _scanSubscription = _ble.scanForDevices(
        withServices: const [], scanMode: ScanMode.lowLatency).listen((device) {
      if (device.serviceUuids.contains(_service) && !completer.isCompleted) {
        completer.complete(device);
      }
    }, onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    });

    try {
      final device =
          await completer.future.timeout(const Duration(seconds: 20));
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _connecting = true;
        _deviceId = device.id;
        _deviceName = device.name.isEmpty ? device.id : device.name;
      });
      _log('Encontrado $_deviceName (${device.id})');
      _connect(device.id);
    } catch (error, stack) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _recordError('No se encontró el servidor en 20 segundos', error, stack);
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _connect(String deviceId) async {
    _audit('action_connect', params: {'deviceId': deviceId, 'deviceName': _deviceName});
    _log('Conectando físicamente...');
    _connectionSubscription = _ble
        .connectToAdvertisingDevice(
      id: deviceId,
      withServices: [_service],
      prescanDuration: const Duration(seconds: 2),
      connectionTimeout: const Duration(seconds: 12),
      servicesWithCharacteristicsToDiscover: {
        _service: [_characteristic],
      },
    )
        .listen((update) {
      _log('Estado de conexión: ${update.connectionState.name}');
      switch (update.connectionState) {
        case DeviceConnectionState.connected:
          _prepareClient(deviceId);
        case DeviceConnectionState.disconnected:
          _clearClientState('El servidor desconectó al jugador');
        case DeviceConnectionState.connecting:
        case DeviceConnectionState.disconnecting:
          break;
      }
    }, onError: (Object error, StackTrace stack) {
      _recordError('Error de conexión', error, stack);
      _clearClientState('Conexión terminada por error: $error');
    }, onDone: () {
      if (_clientReady || _connecting) {
        _clearClientState('El stream de conexión terminó inesperadamente');
      }
    });
  }

  Future<void> _prepareClient(String deviceId) async {
    if (_clientReady) return;
    try {
      _log('Descubriendo servicio y característica...');
      final characteristic = await _discoverCharacteristicWithRetry(deviceId);
      if (characteristic == null) {
        _log('La característica no apareció; se intentará reconectar...');
        unawaited(_scheduleReconnectAfterFailure());
        throw StateError('El servidor anunciado no publicó la característica');
      }
      _log(
          'Característica encontrada: notify=${characteristic.isNotifiable}, write=${characteristic.isWritableWithResponse}');

      final qualified = QualifiedCharacteristic(
        serviceId: _service,
        characteristicId: _characteristic,
        deviceId: deviceId,
      );
      _notificationSubscription =
          _ble.subscribeToCharacteristic(qualified).listen((bytes) {
        final text = utf8.decode(bytes);
        if (text == '{"type":"pong"}') {
          _lastPongReceived = DateTime.now();
          _pongMissedCount = 0;
          _log('pong recibido');
          return;
        }
        _log('RECIBIDO DEL SERVIDOR: $text');
      }, onError: (Object error, StackTrace stack) {
        _recordError('Falló la suscripción', error, stack);
        _clearClientState('Suscripción terminada');
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _deviceId != deviceId) return;
      setState(() {
        _connecting = false;
        _clientReady = true;
      });
      _startKeepAlive(deviceId);
      _log('CLIENTE LISTO PARA ENVIAR Y RECIBIR');
    } catch (error, stack) {
      _recordError('Error preparando el cliente GATT', error, stack);
      await _stopClient();
    }
  }

  Future<dynamic> _discoverCharacteristicWithRetry(String deviceId) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (_deviceId != deviceId) return null;
      try {
        await _ble.discoverAllServices(deviceId).timeout(
              const Duration(seconds: 4),
            );
        final services = await _ble.getDiscoveredServices(deviceId);
        final service = services.where((item) => item.id == _service).firstOrNull;
        final characteristic = service?.characteristics
            .where((item) => item.id == _characteristic)
            .firstOrNull;
        if (characteristic != null) return characteristic;
        _log('Intento $attempt: característica no encontrada, reintentando...');
      } catch (error) {
        _log('Intento $attempt falló: $error');
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
    return null;
  }

  Future<void> _scheduleReconnectAfterFailure() async {
    final previousDeviceId = _deviceId;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _stopKeepAlive();
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    if (previousDeviceId != null) {
      await _clearBleCacheForDevice(previousDeviceId);
    }
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _clientReady = false;
      _deviceId = null;
      _deviceName = '';
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted && _deviceId == null && !_scanning && !_clientReady) {
      _scanAndConnect();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _audit('tap_send_message', params: {'length': text.length, 'mode': _serverActive ? 'server' : 'client'});
    try {
      if (_serverActive) {
        if (!_serverClientSubscribed) {
          _log('No se puede enviar: el jugador no está suscrito');
          return;
        }
        final sent = await _channel.invokeMethod<bool>(
              'bleSendNotification',
              {'payload': text},
            ) ??
            false;
        if (!sent) throw StateError('Android rechazó la notificación');
        _log('ENVIADO AL JUGADOR: $text');
      } else if (_clientReady && _deviceId != null) {
        final qualified = QualifiedCharacteristic(
          serviceId: _service,
          characteristicId: _characteristic,
          deviceId: _deviceId!,
        );
        await _ble.writeCharacteristicWithResponse(
          qualified,
          value: utf8.encode(text),
        );
        _log('ENVIADO AL SERVIDOR: $text');
      }
      _messageController.clear();
    } catch (error, stack) {
      _recordError('No se pudo enviar el mensaje', error, stack);
    }
  }

  Future<void> _stopClient() async {
    _audit('tap_stop_client');
    _stopKeepAlive();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _connecting = false;
      _clientReady = false;
      _deviceId = null;
      _deviceName = '';
    });
  }

  Future<void> _fullStop() async {
    _audit('action_full_stop');
    final previousDeviceId = _deviceId;
    await _stopServer();
    await _stopClient();
    if (previousDeviceId != null) {
      await _clearBleCacheForDevice(previousDeviceId);
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _clearBleCacheForDevice(String deviceId) async {
    _audit('action_clear_ble_cache', params: {'deviceId': deviceId});
    try {
      await _channel.invokeMethod<bool>('bleUnbondDevice', {'deviceId': deviceId});
    } catch (_) {}
    try {
      await _channel.invokeMethod<bool>('bleRefreshDeviceCache', {'deviceId': deviceId});
    } catch (_) {}
  }

  void _startKeepAlive(String deviceId) {
    _keepAliveTimer?.cancel();
    _lastPongReceived = DateTime.now();
    _pongMissedCount = 0;
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || !_clientReady || _deviceId != deviceId) {
        _keepAliveTimer?.cancel();
        _keepAliveTimer = null;
        return;
      }
      final lastPong = _lastPongReceived;
      if (lastPong != null &&
          DateTime.now().difference(lastPong) > const Duration(seconds: 5)) {
        _pongMissedCount += 1;
        _log('No se recibe pong desde hace 5s (fallo $_pongMissedCount)');
        if (_pongMissedCount >= 2) {
          _log('Conexión perdida por falta de pong. Reconectando...');
          _keepAliveTimer?.cancel();
          _keepAliveTimer = null;
          unawaited(_scheduleReconnectAfterFailure());
          return;
        }
      }
      try {
        final qualified = QualifiedCharacteristic(
          serviceId: _service,
          characteristicId: _characteristic,
          deviceId: deviceId,
        );
        await _ble.writeCharacteristicWithResponse(
          qualified,
          value: utf8.encode('{"type":"ping"}'),
        );
      } catch (error) {
        _log('No se pudo enviar ping: $error');
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _lastPongReceived = null;
    _pongMissedCount = 0;
  }

  void _clearClientState(String reason) {
    _stopKeepAlive();
    unawaited(_notificationSubscription?.cancel());
    _notificationSubscription = null;
    final connection = _connectionSubscription;
    _connectionSubscription = null;
    unawaited(connection?.cancel());
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _clientReady = false;
      _deviceId = null;
      _deviceName = '';
    });
    _log(reason);
  }

  void _log(String message) {
    BleDiagnosticLogger.instance.log('BLE_DEBUG_ISOLATED', message);
    if (!mounted) return;
    final timestamp = TimeOfDay.now().format(context);
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 150) _logs.removeLast();
    });
  }

  void _audit(String action, {Map<String, dynamic>? params}) {
    BleDiagnosticLogger.instance.logEvent('UI_DEBUG', action, params: params);
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final ignoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
      _audit('battery_optimization_check', params: {'ignoring': ignoring});
      if (!ignoring && mounted) {
        _log('Solicitando desactivar optimización de batería...');
        await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
      }
    } catch (error, stack) {
      _recordError('No se pudo verificar optimización de batería', error, stack);
    }
  }

  void _recordError(String message, Object error, StackTrace stack) {
    BleDiagnosticLogger.instance.log(
      'BLE_DEBUG_ISOLATED_ERROR',
      message,
      error: error,
      stack: stack,
    );
    _log('$message: $error');
  }

  Future<void> _resetBleState() async {
    _audit('tap_reset_ble_state');
    _log('REINICIO TOTAL BLE...');
    await _stopServer();
    await _stopClient();
    try {
      await _channel.invokeMethod<void>('bleResetState');
      _log('Estado nativo limpiado');
    } catch (error, stack) {
      _recordError('No se pudo limpiar estado nativo', error, stack);
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _initialize();
    _log('Reinicio completado');
  }

  Future<void> _restartBluetooth() async {
    _audit('tap_restart_bluetooth');
    _log('Reiniciando Bluetooth del sistema...');
    await _stopServer();
    await _stopClient();
    try {
      final ok = await _channel.invokeMethod<bool>('bleRestartBluetooth') ?? false;
      _log(ok ? 'Bluetooth reiniciado' : 'No se pudo reiniciar Bluetooth automáticamente');
      if (!ok) {
        _log('Apagá y encendé Bluetooth manualmente si sigue fallando');
      }
    } catch (error, stack) {
      _recordError('Error reiniciando Bluetooth', error, stack);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await _initialize();
  }

  @override
  void dispose() {
    _stopKeepAlive();
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('stopBleServer'));
    unawaited(_scanSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _serverClientSubscribed || _clientReady;
    final status = _serverStarting
        ? 'Iniciando servidor...'
        : _serverActive
            ? _serverClientSubscribed
                ? 'Servidor: jugador listo'
                : _serverClientConnected
                    ? 'Servidor: preparando jugador'
                    : 'Servidor: esperando jugador'
            : _scanning
                ? 'Buscando servidor...'
                : _connecting
                    ? 'Conectando jugador...'
                    : _clientReady
                        ? 'Jugador conectado'
                        : 'Sin conexión';

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Debug aislado'),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.onOpenGame != null)
            TextButton(
              onPressed: widget.onOpenGame,
              child: const Text('Abrir juego'),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: canSend ? kGreen : kBorder,
                  ),
                ),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: canSend ? kGreen : kTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!_bluetoothReady) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _initialize,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Revisar Bluetooth y permisos'),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _bluetoothReady && !_serverStarting && !_serverActive
                              ? _startServer
                              : null,
                      icon: const Icon(Icons.cell_tower_rounded),
                      label: const Text('Iniciar servidor'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _bluetoothReady &&
                              !_scanning &&
                              !_connecting &&
                              !_clientReady
                          ? _scanAndConnect
                          : null,
                      icon: const Icon(Icons.bluetooth_searching_rounded),
                      label: const Text('Conectar jugador'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: (_serverActive ||
                        _serverStarting ||
                        _scanning ||
                        _connecting ||
                        _clientReady)
                    ? _fullStop
                    : null,
                child: const Text('Detener todo'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _resetBleState,
                      icon: const Icon(Icons.cleaning_services_rounded),
                      label: const Text('Reset BLE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _restartBluetooth,
                      icon: const Icon(Icons.bluetooth_disabled_rounded),
                      label: const Text('Reiniciar BT'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: canSend,
                      maxLength: 100,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        labelText: 'Mensaje simple',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: canSend ? _sendMessage : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Log de esta sesión',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF060B14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (_, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        _logs[index],
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
