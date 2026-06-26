import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';

enum BleAvailabilityStatus {
  ready,
  noHardware,
  missingPermissions,
  bluetoothOff,
  unknownError,
}

class BleContactProfile {
  final String label;
  final String helper;
  final int rssiThreshold;
  final int requiredSamples;

  const BleContactProfile({
    required this.label,
    required this.helper,
    required this.rssiThreshold,
    required this.requiredSamples,
  });
}

const kBleContactProfiles = [
  BleContactProfile(
    label: 'Muy estricto',
    helper: 'Solo cuando están casi pegados',
    rssiThreshold: -10,
    requiredSamples: 8,
  ),
  BleContactProfile(
    label: 'Estricto',
    helper: 'Contacto muy cercano',
    rssiThreshold: -15,
    requiredSamples: 5,
  ),
  BleContactProfile(
    label: 'Normal',
    helper: 'Cercanía corta para juego',
    rssiThreshold: -29,
    requiredSamples: 4,
  ),
  BleContactProfile(
    label: 'Flexible',
    helper: 'Permite acercamiento cómodo',
    rssiThreshold: -42,
    requiredSamples: 3,
  ),
  BleContactProfile(
    label: 'Lejos',
    helper: 'Más permisivo',
    rssiThreshold: -57,
    requiredSamples: 2,
  ),
];

const int kBleDefaultContactProfileIndex = 0;

class BleBankDevice {
  final String id;
  final String name;
  final int rssi;

  const BleBankDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  String get proximityLabel {
    if (rssi >= -5) return 'Contacto';
    if (rssi >= -55) return 'Acerca más';
    return 'Fuera de contacto';
  }
}

class BleConnectedPlayer {
  final String id;
  final String name;
  final bool subscribed;
  final int? rssi;
  final bool contactReady;
  final DateTime lastSeen;

  const BleConnectedPlayer({
    required this.id,
    required this.name,
    required this.subscribed,
    required this.rssi,
    required this.contactReady,
    required this.lastSeen,
  });

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    final suffix = id.length > 5 ? id.substring(id.length - 5) : id;
    return 'Jugador $suffix';
  }

  String get qualityLabel {
    if (!subscribed) return 'Preparando';
    final value = rssi;
    if (value == null) return 'Conectado';
    if (contactReady) return 'Contacto';
    if (value >= -55) return 'Buena';
    if (value >= -70) return 'Media';
    return 'Débil';
  }

  Color get qualityColor {
    if (!subscribed) return Colors.blue;
    if (contactReady) return kGreen;
    final value = rssi;
    if (value == null) return Colors.blue;
    if (value >= -55) return kGreen;
    if (value >= -70) return kGold;
    return kRed;
  }

  BleConnectedPlayer copyWith({
    String? name,
    bool? subscribed,
    int? rssi,
    bool? contactReady,
    DateTime? lastSeen,
  }) {
    return BleConnectedPlayer(
      id: id,
      name: name ?? this.name,
      subscribed: subscribed ?? this.subscribed,
      rssi: rssi ?? this.rssi,
      contactReady: contactReady ?? this.contactReady,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class BleTransport extends P2PTransport {
  @override
  String get name => 'Bluetooth';

  @override
  IconData get icon => Icons.bluetooth_rounded;

  @override
  String get description =>
      'Conexi\u00f3n Bluetooth directa entre dispositivos';

  @override
  bool get isEnabled => _hardwareAvailable;

  static const _channel = MethodChannel('com.monopoly/ble');

  static const String _serviceUuid = '12345678-0000-1000-8000-00805f9b34fb';
  static const String _charUuid = '12345678-0001-1000-8000-00805f9b34fb';

  final _ble = FlutterReactiveBle();

  bool _hardwareAvailable = false;
  bool _initialized = false;
  bool _isBank = false;
  bool _serverActive = false;
  BleAvailabilityStatus _availabilityStatus =
      BleAvailabilityStatus.unknownError;

  BleAvailabilityStatus get availabilityStatus => _availabilityStatus;

  final ValueNotifier<bool> serverActiveNotifier = ValueNotifier(false);
  final ValueNotifier<bool> clientConnectedNotifier = ValueNotifier(false);
  final ValueNotifier<String> connectionStatusNotifier = ValueNotifier('');
  final ValueNotifier<String> connectedDeviceNameNotifier = ValueNotifier('');
  final ValueNotifier<List<BleBankDevice>> discoveredBanksNotifier =
      ValueNotifier(const []);
  final ValueNotifier<List<BleConnectedPlayer>> connectedPlayersNotifier =
      ValueNotifier(const []);
  final ValueNotifier<bool> contactReadyNotifier = ValueNotifier(false);
  final ValueNotifier<int?> contactRssiNotifier = ValueNotifier(null);
  final ValueNotifier<int> contactProfileIndexNotifier =
      ValueNotifier(kBleDefaultContactProfileIndex);

  // Client mode (player)
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _proximityTimer;
  int _nearContactSampleCount = 0;
  bool _proximityBusy = false;
  bool _clientConnected = false;
  String? _connectedDeviceId;
  void Function(Map<String, dynamic>)? _receiveCallback;

  BleTransport() {
    _channel.setMethodCallHandler(_handleNativeCalls);
  }

  BleContactProfile get contactProfile =>
      kBleContactProfiles[contactProfileIndexNotifier.value];

  bool isRssiContactReady(int rssi) => rssi >= contactProfile.rssiThreshold;

  String proximityLabelFor(int rssi) {
    if (isRssiContactReady(rssi)) return 'Contacto';
    if (rssi >= -55) return 'Acerca más';
    return 'Fuera de contacto';
  }

  Future<void> setContactProfileIndex(int index) async {
    final clamped = index.clamp(0, kBleContactProfiles.length - 1) as int;
    contactProfileIndexNotifier.value = clamped;
    await HiveService.settingsBox.put('ble_contact_profile_index', clamped);
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;
    _nearContactSampleCount = 0;
  }

  String? _deviceIdFrom(dynamic arguments) {
    if (arguments is String && arguments.isNotEmpty) return arguments;
    if (arguments is Map) return arguments['deviceId'] as String?;
    return null;
  }

  String _deviceNameFrom(dynamic arguments) {
    if (arguments is Map) return (arguments['deviceName'] as String?) ?? '';
    return '';
  }

  String _payloadFrom(dynamic arguments) {
    if (arguments is Map) return (arguments['payload'] as String?) ?? '';
    return arguments as String;
  }

  void _upsertConnectedPlayer(
    String? id, {
    String? name,
    bool? subscribed,
    int? rssi,
    bool? contactReady,
  }) {
    if (id == null || id.isEmpty) return;
    final next = [...connectedPlayersNotifier.value];
    final index = next.indexWhere((player) => player.id == id);
    if (index >= 0) {
      next[index] = next[index].copyWith(
        name: name?.trim().isNotEmpty == true ? name : null,
        subscribed: subscribed,
        rssi: rssi,
        contactReady: contactReady,
        lastSeen: DateTime.now(),
      );
    } else {
      next.add(
        BleConnectedPlayer(
          id: id,
          name: name?.trim() ?? '',
          subscribed: subscribed ?? false,
          rssi: rssi,
          contactReady: contactReady ?? false,
          lastSeen: DateTime.now(),
        ),
      );
    }
    next.sort((a, b) {
      final readyCompare = (b.subscribed ? 1 : 0) - (a.subscribed ? 1 : 0);
      if (readyCompare != 0) return readyCompare;
      return b.lastSeen.compareTo(a.lastSeen);
    });
    connectedPlayersNotifier.value = next;
    clientConnectedNotifier.value = next.any((player) => player.subscribed);
    connectedDeviceNameNotifier.value =
        next.isEmpty ? '' : next.first.displayName;
  }

  void _removeConnectedPlayer(String? id) {
    if (id == null || id.isEmpty) return;
    final next = connectedPlayersNotifier.value
        .where((player) => player.id != id)
        .toList(growable: false);
    connectedPlayersNotifier.value = next;
    clientConnectedNotifier.value = next.any((player) => player.subscribed);
    connectedDeviceNameNotifier.value =
        next.isEmpty ? '' : next.first.displayName;
  }

  Future<dynamic> _handleNativeCalls(MethodCall call) async {
    switch (call.method) {
      case 'bleDataReceived':
        try {
          final deviceId = _deviceIdFrom(call.arguments);
          final deviceName = _deviceNameFrom(call.arguments);
          final jsonStr = _payloadFrom(call.arguments);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (deviceId != null) data['_bleDeviceId'] = deviceId;
          if (_isBank && data['type'] == 'ble_proximity') {
            final rssi = (data['rssi'] as num?)?.toInt();
            if (rssi != null) {
              final ready =
                  data['contactReady'] == true && isRssiContactReady(rssi);
              contactRssiNotifier.value = rssi;
              contactReadyNotifier.value = ready;
              _upsertConnectedPlayer(
                deviceId,
                name: deviceName,
                subscribed: true,
                rssi: rssi,
                contactReady: ready,
              );
            }
          } else if (_isBank) {
            final name = data['name'] as String?;
            _upsertConnectedPlayer(
              deviceId,
              name: name?.trim().isNotEmpty == true ? name : deviceName,
              subscribed: true,
            );
          }
          _receiveCallback?.call(data);
        } catch (_) {}
        break;
      case 'bleClientConnected':
        _upsertConnectedPlayer(
          _deviceIdFrom(call.arguments),
          name: _deviceNameFrom(call.arguments),
          subscribed: false,
        );
        if (_isBank) {
          connectionStatusNotifier.value =
              'Jugador conectado. Preparando canal BLE...';
        }
        break;
      case 'bleClientSubscribed':
        _upsertConnectedPlayer(
          _deviceIdFrom(call.arguments),
          name: _deviceNameFrom(call.arguments),
          subscribed: true,
        );
        contactReadyNotifier.value = false;
        contactRssiNotifier.value = null;
        if (_isBank) {
          connectionStatusNotifier.value =
              'Jugador conectado al banco y listo para recibir';
        }
        break;
      case 'bleClientUnsubscribed':
        _upsertConnectedPlayer(
          _deviceIdFrom(call.arguments),
          name: _deviceNameFrom(call.arguments),
          subscribed: false,
          contactReady: false,
        );
        contactReadyNotifier.value = false;
        contactRssiNotifier.value = null;
        if (_isBank && _serverActive) {
          connectionStatusNotifier.value =
              'Jugador conectado, esperando que quede listo para recibir...';
        }
        break;
      case 'bleClientDisconnected':
        _removeConnectedPlayer(_deviceIdFrom(call.arguments));
        contactReadyNotifier.value = false;
        contactRssiNotifier.value = null;
        if (_isBank && _serverActive) {
          connectionStatusNotifier.value =
              'Servidor activo. Esperando que un jugador se conecte...';
        }
        break;
    }
    return null;
  }

  void setBankMode(bool isBank) {
    _isBank = isBank;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final storedProfile =
        HiveService.settingsBox.get('ble_contact_profile_index');
    if (storedProfile is int &&
        storedProfile >= 0 &&
        storedProfile < kBleContactProfiles.length) {
      contactProfileIndexNotifier.value = storedProfile;
    }

    await requestPermissions();
    await refreshAvailability();
  }

  Future<bool> requestPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestBlePermissions') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<BleAvailabilityStatus> refreshAvailability() async {
    try {
      final hasHardware =
          await _channel.invokeMethod<bool>('hasBleHardware') ?? false;
      if (!hasHardware) {
        _hardwareAvailable = false;
        _availabilityStatus = BleAvailabilityStatus.noHardware;
        return _availabilityStatus;
      }

      final hasPermissions =
          await _channel.invokeMethod<bool>('hasBlePermissions') ?? false;
      if (!hasPermissions) {
        _hardwareAvailable = false;
        _availabilityStatus = BleAvailabilityStatus.missingPermissions;
        return _availabilityStatus;
      }

      final isEnabled =
          await _channel.invokeMethod<bool>('isBleEnabled') ?? false;
      if (!isEnabled) {
        _hardwareAvailable = false;
        _availabilityStatus = BleAvailabilityStatus.bluetoothOff;
        return _availabilityStatus;
      }

      _hardwareAvailable = true;
      _availabilityStatus = BleAvailabilityStatus.ready;
    } catch (_) {
      _hardwareAvailable = false;
      _availabilityStatus = BleAvailabilityStatus.unknownError;
    }
    return _availabilityStatus;
  }

  Future<void> openBleSettings() async {
    await _channel.invokeMethod('openBleSettings');
  }

  @override
  Future<void> startReceiving(
      void Function(Map<String, dynamic>) onData) async {
    _receiveCallback = onData;

    if (_isBank) {
      await _startBankServer();
    } else {
      await _startClientScan(onData);
    }
  }

  // ── Modo BANCO: Servidor GATT ────────────────────────────────────

  Future<void> _startBankServer() async {
    if (_serverActive) return;
    _serverActive = true;
    serverActiveNotifier.value = true;
    connectedPlayersNotifier.value = const [];
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;
    connectionStatusNotifier.value = 'Iniciando servidor BLE...';

    try {
      await _channel.invokeMethod('startBleServer', {
        'serviceUuid': _serviceUuid,
        'charUuid': _charUuid,
      });
      connectionStatusNotifier.value =
          'Servidor activo. Esperando que un jugador se conecte...';
    } catch (e) {
      _serverActive = false;
      serverActiveNotifier.value = false;
      connectionStatusNotifier.value = 'Error al iniciar servidor BLE';
    }
  }

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    if (_isBank) {
      await _sendViaServer(payload);
    } else {
      await _sendViaClient(payload);
    }
  }

  Future<void> _sendViaServer(Map<String, dynamic> payload) async {
    if (!_serverActive) {
      throw TransportUnavailableException('Servidor BLE apagado');
    }

    try {
      final jsonStr = jsonEncode(payload);
      final sent = await _channel.invokeMethod<bool>('bleSendNotification', {
            'payload': jsonStr,
          }) ??
          false;
      if (!sent) {
        final status =
            await _channel.invokeMethod<Map>('bleIsClientConnected') ?? {};
        if (status['subscribed'] != true) {
          throw TransportUnavailableException(
            'El jugador todavía no está listo para recibir datos por BLE. Espera a que aparezca conectado al banco.',
          );
        }
        throw TransportUnavailableException(
            'Fallo al enviar notificaci\u00f3n BLE');
      }
    } catch (e) {
      if (e is TransportUnavailableException) rethrow;
      throw TransportUnavailableException('Error BLE: $e');
    }
  }

  // ── Modo CLIENTE: escanear y conectar ────────────────────────────

  Future<void> _startClientScan(
      void Function(Map<String, dynamic>) onData) async {
    _receiveCallback = onData;
    _clientConnected = false;
    _nearContactSampleCount = 0;
    clientConnectedNotifier.value = false;
    connectionStatusNotifier.value = 'Buscando bancos por Bluetooth...';
    discoveredBanksNotifier.value = const [];

    final serviceUuid = Uuid.parse(_serviceUuid);
    _scanSub = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (_clientConnected) return;
      final suffix =
          device.id.length > 6 ? device.id.substring(0, 6) : device.id;
      final displayName =
          device.name.trim().isEmpty ? 'Banco cercano $suffix' : device.name;
      final next = [...discoveredBanksNotifier.value];
      final index = next.indexWhere((bank) => bank.id == device.id);
      final bank = BleBankDevice(
        id: device.id,
        name: displayName,
        rssi: device.rssi,
      );
      if (index >= 0) {
        next[index] = bank;
      } else {
        next.add(bank);
      }
      next.sort((a, b) => b.rssi.compareTo(a.rssi));
      discoveredBanksNotifier.value = next;
      if (_receiveCallback != null) return;

      _scanSub?.cancel();
      _scanSub = null;

      connectedDeviceNameNotifier.value = device.name;
      connectionStatusNotifier.value = 'Conectando a ${device.name}...';
      _connectedDeviceId = device.id;
      _connectSub = _ble.connectToDevice(
        id: device.id,
        servicesWithCharacteristicsToDiscover: {
          Uuid.parse(_serviceUuid): [Uuid.parse(_charUuid)],
        },
      ).listen((state) {
        if (state.connectionState == DeviceConnectionState.connected) {
          _clientConnected = true;
          clientConnectedNotifier.value = true;
          connectionStatusNotifier.value = 'Conectado al banco';
          _prepareNotificationChannel(device.id);
        } else if (state.connectionState ==
            DeviceConnectionState.disconnecting) {
          connectionStatusNotifier.value = 'Desconectando...';
        } else if (state.connectionState ==
            DeviceConnectionState.disconnected) {
          _clientConnected = false;
          _proximityTimer?.cancel();
          _proximityTimer = null;
          _proximityBusy = false;
          _nearContactSampleCount = 0;
          contactReadyNotifier.value = false;
          contactRssiNotifier.value = null;
          clientConnectedNotifier.value = false;
          _connectedDeviceId = null;
          connectedDeviceNameNotifier.value = '';
          connectionStatusNotifier.value = 'Desconectado';
          if (_receiveCallback != null) {
            _reconnectScan();
          }
        }
      }, onError: (_) {
        _clientConnected = false;
        _proximityBusy = false;
        _nearContactSampleCount = 0;
        clientConnectedNotifier.value = false;
        connectionStatusNotifier.value = 'Error de conexión, reconectando...';
        Future.delayed(const Duration(seconds: 2), _reconnectScan);
      });
    }, onError: (_) {
      connectionStatusNotifier.value = 'Error al escanear, reintentando...';
      Future.delayed(const Duration(seconds: 3), _reconnectScan);
    });
  }

  Future<void> connectToBank(BleBankDevice bank) async {
    _isBank = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await _connectSub?.cancel();
    _connectSub = null;
    await _notifySub?.cancel();
    _notifySub = null;

    _clientConnected = false;
    _nearContactSampleCount = 0;
    clientConnectedNotifier.value = false;
    connectedDeviceNameNotifier.value = bank.name;
    connectionStatusNotifier.value = 'Conectando a ${bank.name}...';
    _connectedDeviceId = bank.id;

    _connectSub = _ble.connectToDevice(
      id: bank.id,
      servicesWithCharacteristicsToDiscover: {
        Uuid.parse(_serviceUuid): [Uuid.parse(_charUuid)],
      },
    ).listen((state) {
      if (state.connectionState == DeviceConnectionState.connected) {
        _clientConnected = true;
        clientConnectedNotifier.value = true;
        connectionStatusNotifier.value = 'Conectado al banco';
        _prepareNotificationChannel(bank.id);
      } else if (state.connectionState == DeviceConnectionState.disconnecting) {
        connectionStatusNotifier.value = 'Desconectando...';
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        _clientConnected = false;
        _proximityTimer?.cancel();
        _proximityTimer = null;
        _proximityBusy = false;
        _nearContactSampleCount = 0;
        contactReadyNotifier.value = false;
        contactRssiNotifier.value = null;
        clientConnectedNotifier.value = false;
        _connectedDeviceId = null;
        connectedDeviceNameNotifier.value = '';
        connectionStatusNotifier.value = 'Desconectado';
      }
    }, onError: (_) {
      _clientConnected = false;
      _proximityBusy = false;
      _nearContactSampleCount = 0;
      clientConnectedNotifier.value = false;
      connectionStatusNotifier.value = 'Error de conexión';
    });
  }

  void _subscribeToNotifications() {
    if (_connectedDeviceId == null) return;

    _notifySub?.cancel();
    _notifySub = _ble
        .subscribeToCharacteristic(
      QualifiedCharacteristic(
        serviceId: Uuid.parse(_serviceUuid),
        characteristicId: Uuid.parse(_charUuid),
        deviceId: _connectedDeviceId!,
      ),
    )
        .listen((bytes) {
      try {
        final jsonStr = utf8.decode(bytes);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        _receiveCallback?.call(data);
      } catch (_) {}
    }, onError: (_) {
      Future.delayed(const Duration(seconds: 2), _reconnectScan);
    });
  }

  Future<void> _prepareNotificationChannel(String deviceId) async {
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: 247);
    } catch (_) {}

    if (!_clientConnected || _connectedDeviceId != deviceId) return;
    _subscribeToNotifications();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_clientConnected && _connectedDeviceId == deviceId) {
        _startProximityReporting(deviceId);
      }
    });
  }

  void _startProximityReporting(String deviceId) {
    _proximityTimer?.cancel();
    _nearContactSampleCount = 0;
    _proximityBusy = false;
    _proximityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _reportCurrentProximity(deviceId);
    });
    _reportCurrentProximity(deviceId);
  }

  Future<void> _reportCurrentProximity(String deviceId) async {
    if (!_clientConnected || _connectedDeviceId != deviceId) return;
    if (_proximityBusy) return;
    _proximityBusy = true;
    try {
      final rssi = await _ble.readRssi(deviceId);
      if (isRssiContactReady(rssi)) {
        _nearContactSampleCount += 1;
      } else {
        _nearContactSampleCount = 0;
      }
      final contactReady =
          _nearContactSampleCount >= contactProfile.requiredSamples;
      contactRssiNotifier.value = rssi;
      contactReadyNotifier.value = contactReady;
      await _writeClientPayload({
        'type': 'ble_proximity',
        'rssi': rssi,
        'contactReady': contactReady,
      });
    } catch (_) {
      _nearContactSampleCount = 0;
      contactReadyNotifier.value = false;
      contactRssiNotifier.value = null;
    } finally {
      _proximityBusy = false;
    }
  }

  Future<void> _reconnectScan() async {
    final callback = _receiveCallback;
    await stop();
    if (callback != null) {
      _receiveCallback = callback;
      connectionStatusNotifier.value = 'Reconectando...';
      await _startClientScan(callback);
    }
  }

  Future<void> _sendViaClient(Map<String, dynamic> payload) async {
    try {
      await _writeClientPayload(payload);
    } catch (e) {
      _clientConnected = false;
      _proximityBusy = false;
      _nearContactSampleCount = 0;
      _connectedDeviceId = null;
      throw TransportUnavailableException('Error al enviar: $e');
    }
  }

  Future<void> _writeClientPayload(Map<String, dynamic> payload) async {
    if (_connectedDeviceId == null) {
      throw TransportUnavailableException('No hay conexi\u00f3n al banco');
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_charUuid),
      deviceId: _connectedDeviceId!,
    );

    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: utf8.encode(jsonEncode(payload)),
    );
  }

  Future<void> startServer() async {
    _isBank = true;
    await refreshAvailability();
    if (!isEnabled) {
      throw TransportUnavailableException('Bluetooth no est\u00e1 disponible');
    }
    await _startBankServer();
  }

  Future<void> stopServer() async {
    if (!_isBank) return;
    await stop();
  }

  Future<void> startClientScan(
      void Function(Map<String, dynamic>) onData) async {
    _isBank = false;
    await _startClientScan(onData);
  }

  Future<void> stopClientScan() async {
    if (_isBank) return;
    await stop();
  }

  @override
  Future<void> stop() async {
    _receiveCallback = null;
    _clientConnected = false;
    _proximityBusy = false;
    _nearContactSampleCount = 0;
    _connectedDeviceId = null;

    clientConnectedNotifier.value = false;
    connectedDeviceNameNotifier.value = '';
    connectionStatusNotifier.value = '';
    discoveredBanksNotifier.value = const [];
    connectedPlayersNotifier.value = const [];
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;

    await _scanSub?.cancel();
    _scanSub = null;
    await _connectSub?.cancel();
    _connectSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
    _proximityTimer?.cancel();
    _proximityTimer = null;

    if (_isBank) {
      _serverActive = false;
      serverActiveNotifier.value = false;
      connectionStatusNotifier.value = '';
      try {
        await _channel.invokeMethod('stopBleServer');
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectSub?.cancel();
    _notifySub?.cancel();
    _proximityTimer?.cancel();
    _receiveCallback = null;
    discoveredBanksNotifier.dispose();
    connectedPlayersNotifier.dispose();
    contactReadyNotifier.dispose();
    contactRssiNotifier.dispose();
    contactProfileIndexNotifier.dispose();
    _channel.setMethodCallHandler(null);
  }
}
