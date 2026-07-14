import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/device_identity_service.dart';
import 'package:monopoly_banking/services/app_audit_logger.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/ble_protocol.dart';

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
    helper: 'Dispositivos pegados',
    rssiThreshold: -10,
    requiredSamples: 1,
  ),
  BleContactProfile(
    label: 'Estricto',
    helper: 'Contacto muy cercano',
    rssiThreshold: -15,
    requiredSamples: 1,
  ),
  BleContactProfile(
    label: 'Normal',
    helper: 'Cercanía corta para juego',
    rssiThreshold: -20,
    requiredSamples: 1,
  ),
  BleContactProfile(
    label: 'Flexible',
    helper: 'Permite acercamiento cómodo',
    rssiThreshold: -30,
    requiredSamples: 1,
  ),
  BleContactProfile(
    label: 'Lejos',
    helper: 'Más permisivo',
    rssiThreshold: -50,
    requiredSamples: 1,
  ),
];

const int kBleDefaultContactProfileIndex = 2;

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
  final String deviceName;
  final String deviceInstallationId;
  final bool subscribed;
  final bool playing;
  final int? rssi;
  final bool contactReady;
  final DateTime lastSeen;
  final String avatarId;
  final String colorId;

  const BleConnectedPlayer({
    required this.id,
    required this.name,
    required this.deviceName,
    required this.deviceInstallationId,
    required this.subscribed,
    required this.playing,
    required this.rssi,
    required this.contactReady,
    required this.lastSeen,
    this.avatarId = '',
    this.colorId = '0',
  });

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (deviceName.trim().isNotEmpty) return deviceName.trim();
    return 'Jugador conectado';
  }

  String get displayDeviceName {
    if (deviceName.trim().isNotEmpty) return deviceName.trim();
    if (name.trim().isNotEmpty) return 'Dispositivo de $name';
    return 'Dispositivo conectado';
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
    String? deviceName,
    String? deviceInstallationId,
    bool? subscribed,
    bool? playing,
    int? rssi,
    bool? contactReady,
    DateTime? lastSeen,
    String? avatarId,
    String? colorId,
  }) {
    return BleConnectedPlayer(
      id: id,
      name: name ?? this.name,
      deviceName: deviceName ?? this.deviceName,
      deviceInstallationId: deviceInstallationId ?? this.deviceInstallationId,
      subscribed: subscribed ?? this.subscribed,
      playing: playing ?? this.playing,
      rssi: rssi ?? this.rssi,
      contactReady: contactReady ?? this.contactReady,
      lastSeen: lastSeen ?? this.lastSeen,
      avatarId: avatarId ?? this.avatarId,
      colorId: colorId ?? this.colorId,
    );
  }
}

class _BleChunkBuffer {
  _BleChunkBuffer(this.total)
      : parts = List<String?>.filled(total, null),
        createdAt = DateTime.now();

  final int total;
  final List<String?> parts;
  final DateTime createdAt;
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

  static const String _serviceUuid = BleProtocol.serviceUuid;
  static const String _charUuid = BleProtocol.characteristicUuid;

  final _ble = FlutterReactiveBle();

  bool _hardwareAvailable = false;
  bool _initialized = false;
  bool _isBank = false;
  bool _serverActive = false;
  bool _serverStarting = false;
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
  Timer? _bankConnectionWatchdog;
  Timer? _keepAliveTimer;
  Timer? _proximityPollTimer;
  DateTime? _lastPongReceived;
  int _pongMissedCount = 0;
  final Map<String, int> _bankContactSampleCounts = {};
  bool _clientConnected = false;
  bool _clientCharacteristicReady = false;
  bool _preparingNotificationChannel = false;
  bool _reconnectAllowed = false;
  bool _isReconnecting = false;
  bool _notificationRetryScheduled = false;
  bool _transportDisposed = false;
  Timer? _scanRefreshTimer;
  Completer<DiscoveredDevice>? _pendingScanCompleter;
  String? _connectedDeviceId;
  Map<String, dynamic>? _clientIdentity;
  Future<void> _clientWriteChain = Future<void>.value();
  final Map<String, _BleChunkBuffer> _incomingChunks = {};
  int _chunkMessageCounter = 0;
  int _scanGeneration = 0;
  void Function(Map<String, dynamic>)? _receiveCallback;

  BleTransport() {
    AppAuditLogger.instance.event('LIFECYCLE', 'BleTransport.created');
    _channel.setMethodCallHandler(_handleNativeCalls);
  }

  void _audit(String action, {Map<String, dynamic>? data}) {
    AppAuditLogger.instance.event('BLE_TRANSPORT', action, data: data);
  }

  Future<void> _checkBatteryOptimizationAndKeepScreenOn() async {
    try {
      final ignoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
      _audit('battery_optimization_check', data: {'ignoring': ignoring});
      if (!ignoring) {
        await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
      }
      await _channel.invokeMethod<void>('keepScreenOn', {'keepOn': true});
    } catch (error, stack) {
      AppAuditLogger.instance.event(
        'BLE_TRANSPORT',
        'No se pudo configurar wake lock/batería',
        error: error,
        stack: stack,
      );
    }
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

  BleContactProfile get contactProfile =>
      kBleContactProfiles[contactProfileIndexNotifier.value];

  bool isRssiContactReady(int rssi) => rssi >= contactProfile.rssiThreshold;

  Future<int?> readCurrentRssi() async {
    final deviceId = _connectedDeviceId;
    if (!_clientConnected || deviceId == null) return null;
    try {
      return await _ble.readRssi(deviceId).timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw TimeoutException('readRssi timeout'),
          );
    } catch (_) {
      return null;
    }
  }

  String proximityLabelFor(int rssi) {
    if (isRssiContactReady(rssi)) return 'Contacto';
    if (rssi >= -55) return 'Acerca más';
    return 'Fuera de contacto';
  }

  Future<void> setContactProfileIndex(int index) async {
    final clamped = index.clamp(0, kBleContactProfiles.length - 1);
    contactProfileIndexNotifier.value = clamped;
    await HiveService.settingsBox.put('ble_contact_profile_index', clamped);
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;
    _bankContactSampleCounts.clear();
  }

  void setClientIdentity({
    required String name,
    required String avatarId,
    required String colorId,
    required bool isHandshakeDone,
  }) {
    _clientIdentity = {
      'type': 'ble_identity',
      'playerId': name,
      'name': name,
      'avatarId': avatarId,
      'colorId': colorId,
      'isHandshakeDone': isHandshakeDone,
      'deviceInstallationId': DeviceIdentityService.installationId,
    };
  }

  Future<void> _sendIdentityOnce() async {
    final identity = _clientIdentity;
    if (identity == null || !_clientConnected || _connectedDeviceId == null) {
      return;
    }
    try {
      await _writeClientPayload(identity);
    } catch (_) {}
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

  List<String> _encodeBleFrames(Map<String, dynamic> payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    if (bytes.length <= 180) return [utf8.decode(bytes)];

    const chunkSize = 100;
    final total = (bytes.length / chunkSize).ceil();
    final messageId =
        '${DateTime.now().microsecondsSinceEpoch}-${_chunkMessageCounter++}';
    return List<String>.generate(total, (index) {
      final start = index * chunkSize;
      final end = math.min(start + chunkSize, bytes.length);
      return jsonEncode({
        '_c': messageId,
        'i': index,
        'n': total,
        'd': base64Encode(bytes.sublist(start, end)),
      });
    });
  }

  Map<String, dynamic>? _decodeBleFrame(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final messageId = decoded['_c'] as String?;
    if (messageId == null) return decoded;
    final index = (decoded['i'] as num?)?.toInt();
    final total = (decoded['n'] as num?)?.toInt();
    final data = decoded['d'] as String?;
    if (index == null ||
        total == null ||
        data == null ||
        total <= 0 ||
        index < 0 ||
        index >= total) {
      return null;
    }

    _incomingChunks.removeWhere(
      (_, buffer) =>
          DateTime.now().difference(buffer.createdAt) >
          const Duration(seconds: 15),
    );
    final buffer = _incomingChunks.putIfAbsent(
      messageId,
      () => _BleChunkBuffer(total),
    );
    if (buffer.total != total) {
      _incomingChunks.remove(messageId);
      return null;
    }
    buffer.parts[index] = data;
    if (buffer.parts.any((part) => part == null)) return null;

    _incomingChunks.remove(messageId);
    final bytes = <int>[];
    for (final part in buffer.parts) {
      bytes.addAll(base64Decode(part!));
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  void _upsertConnectedPlayer(
    String? id, {
    String? name,
    String? deviceName,
    String? deviceInstallationId,
    bool? subscribed,
    bool? playing,
    int? rssi,
    bool? contactReady,
    String? avatarId,
    String? colorId,
  }) {
    if (id == null || id.isEmpty) return;
    final next = [...connectedPlayersNotifier.value];
    final index = next.indexWhere((player) => player.id == id);
    if (index >= 0) {
      next[index] = next[index].copyWith(
        name: name?.trim().isNotEmpty == true ? name : null,
        deviceName: deviceName?.trim().isNotEmpty == true ? deviceName : null,
        deviceInstallationId: deviceInstallationId?.trim().isNotEmpty == true
            ? deviceInstallationId
            : null,
        subscribed: subscribed,
        playing: playing,
        rssi: rssi,
        contactReady: contactReady,
        lastSeen: DateTime.now(),
        avatarId: avatarId?.trim().isNotEmpty == true ? avatarId : null,
        colorId: colorId?.trim().isNotEmpty == true ? colorId : null,
      );
    } else {
      next.add(
        BleConnectedPlayer(
          id: id,
          name: name?.trim() ?? '',
          deviceName: deviceName?.trim() ?? '',
          deviceInstallationId: deviceInstallationId?.trim() ?? '',
          subscribed: subscribed ?? false,
          playing: playing ?? false,
          rssi: rssi,
          contactReady: contactReady ?? false,
          lastSeen: DateTime.now(),
          avatarId: avatarId?.trim() ?? '',
          colorId: colorId?.trim() ?? '0',
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
    _bankContactSampleCounts.remove(id);
    final next = connectedPlayersNotifier.value
        .where((player) => player.id != id)
        .toList(growable: false);
    connectedPlayersNotifier.value = next;
    clientConnectedNotifier.value = next.any((player) => player.subscribed);
    connectedDeviceNameNotifier.value =
        next.isEmpty ? '' : next.first.displayName;
  }

  void _startBankConnectionWatchdog() {
    // Desactivado: los jugadores nunca deben desconectarse por inactividad.
    // El keepalive ping/pong mantiene la conexión viva.
    _bankConnectionWatchdog?.cancel();
    _bankConnectionWatchdog = null;
  }

  void _pruneStaleBankPlayers() {
    if (!_isBank || !_serverActive) return;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    final current = connectedPlayersNotifier.value;
    final staleIds = current
        .where((player) => player.lastSeen.isBefore(cutoff))
        .map((player) => player.id)
        .toSet();
    if (staleIds.isEmpty) return;

    AppAuditLogger.instance.event(
      'BLE_BANK',
      'pruning_stale_players',
      data: {'staleIds': staleIds.toList(), 'count': staleIds.length},
    );

    for (final id in staleIds) {
      _bankContactSampleCounts.remove(id);
      unawaited(
        _channel.invokeMethod<bool>('bleDisconnectClient', {'deviceId': id}),
      );
    }
    final next = current
        .where((player) => !staleIds.contains(player.id))
        .toList(growable: false);
    connectedPlayersNotifier.value = next;
    clientConnectedNotifier.value = next.any((player) => player.subscribed);
    connectedDeviceNameNotifier.value =
        next.isEmpty ? '' : next.first.displayName;
    if (next.isEmpty) {
      contactReadyNotifier.value = false;
      contactRssiNotifier.value = null;
      connectionStatusNotifier.value =
          'Servidor activo. Esperando que un jugador se conecte...';
    }
  }

  Future<dynamic> _handleNativeCalls(MethodCall call) async {
    AppAuditLogger.instance.event(
      'BLE_NATIVE',
      '${call.method}: ${call.arguments}',
    );
    _audit('native_${call.method}', data: _safeArgs(call.arguments));
    switch (call.method) {
      case 'bleDataReceived':
        try {
          final deviceId = _deviceIdFrom(call.arguments);
          final deviceName = _deviceNameFrom(call.arguments);
          final jsonStr = _payloadFrom(call.arguments);
          if (_isBank && jsonStr == '{"type":"ping"}') {
            _audit('received_ping');
            await _channel.invokeMethod<bool>('bleSendNotification', {
              'payload': '{"type":"pong"}',
            });
            break;
          }
          final data = _decodeBleFrame(jsonStr);
          if (data == null) break;
          if (deviceId != null) data['_bleDeviceId'] = deviceId;
          if (_isBank && data['type'] == 'player_keepalive') {
            final playerId = data['playerId'] as String? ?? '';
            final avatarId = data['avatarId'] as String? ?? '';
            _audit('received_player_keepalive',
                data: {'playerId': playerId, 'avatarId': avatarId});
            debugPrint(
                '[BLE bank] Recibe player_keepalive: playerId=$playerId, avatarId=$avatarId');
            await _channel.invokeMethod<bool>('bleSendNotification', {
              'payload': jsonEncode({
                'type': 'keepalive_ack',
                'ts': DateTime.now().millisecondsSinceEpoch,
              }),
            });
            break;
          }
          if (_isBank && data['type'] == 'ble_proximity') {
            final rawRssi = data['rssi'] as num?;
            final rssi =
                rawRssi != null && rawRssi.isFinite ? rawRssi.toInt() : null;
            if (rssi != null) {
              final contactKey = deviceId ?? 'unknown';
              if (isRssiContactReady(rssi)) {
                _bankContactSampleCounts[contactKey] =
                    (_bankContactSampleCounts[contactKey] ?? 0) + 1;
              } else {
                _bankContactSampleCounts[contactKey] = 0;
              }
              final ready = (_bankContactSampleCounts[contactKey] ?? 0) >=
                  contactProfile.requiredSamples;
              contactRssiNotifier.value = rssi;
              contactReadyNotifier.value = ready;
              _upsertConnectedPlayer(
                deviceId,
                deviceName: deviceName,
                subscribed: true,
                rssi: rssi,
                contactReady: ready,
              );
            }
          } else if (_isBank) {
            final name = data['name'] as String?;
            final deviceInstallationId =
                data['deviceInstallationId'] as String?;
            final type = data['type'] as String?;
            final avatarId = data['avatarId'] as String?;
            final colorId = data['colorId'] as String?;
            _upsertConnectedPlayer(
              deviceId,
              name: name?.trim().isNotEmpty == true ? name : null,
              deviceName: deviceName,
              deviceInstallationId: deviceInstallationId,
              subscribed: true,
              playing: type == 'handshake_confirm' ? true : null,
              avatarId: avatarId,
              colorId: colorId,
            );
          }
          _receiveCallback?.call(data);
        } catch (_) {}
        break;
      case 'bleClientConnected':
        final connectedDeviceId = _deviceIdFrom(call.arguments);
        final deviceNameArg = _deviceNameFrom(call.arguments);
        if (connectedDeviceId != null) {
          _bankContactSampleCounts.remove(connectedDeviceId);
        }
        _upsertConnectedPlayer(
          connectedDeviceId,
          deviceName: deviceNameArg,
          subscribed: false,
          playing: false,
          contactReady: false,
        );
        if (_isBank) {
          final label = deviceNameArg.isNotEmpty
              ? deviceNameArg
              : 'Nuevo dispositivo';
          connectionStatusNotifier.value =
              '$label conectado. Preparando canal BLE...';
        }
        break;
      case 'bleClientSubscribed':
        _upsertConnectedPlayer(
          _deviceIdFrom(call.arguments),
          deviceName: _deviceNameFrom(call.arguments),
          subscribed: true,
          playing: false,
          contactReady: false,
        );
        if (connectedPlayersNotifier.value.every(
            (player) => !player.contactReady)) {
          contactReadyNotifier.value = false;
          contactRssiNotifier.value = null;
        }
        if (_isBank) {
          final player = connectedPlayersNotifier.value
              .firstWhere((p) => p.id == _deviceIdFrom(call.arguments),
                  orElse: () => BleConnectedPlayer(
                      id: '', name: '', deviceName: '',
                      deviceInstallationId: '', subscribed: true,
                      playing: false, rssi: null,
                      contactReady: false,
                      lastSeen: DateTime.now()));
          final label = player.displayName;
          connectionStatusNotifier.value =
              '$label conectado al banco y listo para recibir';
        }
        break;
      case 'bleClientUnsubscribed':
        _upsertConnectedPlayer(
          _deviceIdFrom(call.arguments),
          deviceName: _deviceNameFrom(call.arguments),
          subscribed: false,
          contactReady: false,
        );
        if (connectedPlayersNotifier.value.every(
            (player) => !player.contactReady)) {
          contactReadyNotifier.value = false;
          contactRssiNotifier.value = null;
        }
        if (_isBank && _serverActive) {
          connectionStatusNotifier.value =
              'Esperando que el jugador quede listo...';
        }
        break;
      case 'bleClientDisconnected':
        final deviceId = _deviceIdFrom(call.arguments);
        final status = call.arguments is Map ? (call.arguments as Map)['status']?.toString() : null;
        _audit('native_bleClientDisconnected', data: {'deviceId': deviceId, 'status': status});
        _removeConnectedPlayer(deviceId);
        contactReadyNotifier.value = false;
        contactRssiNotifier.value = null;
        if (_isBank && _serverActive) {
          connectionStatusNotifier.value =
              'Servidor activo. Esperando que un jugador se conecte...';
        }
        break;
      case 'bleServerAdvertisingStarted':
        _serverStarting = false;
        _serverActive = true;
        serverActiveNotifier.value = true;
        connectionStatusNotifier.value =
            'Servidor activo. Esperando que un jugador se conecte...';
        _startBankConnectionWatchdog();
        break;
      case 'bleServerAdvertisingFailed':
        _serverStarting = false;
        _serverActive = false;
        serverActiveNotifier.value = false;
        connectedPlayersNotifier.value = const [];
        clientConnectedNotifier.value = false;
        _bankConnectionWatchdog?.cancel();
        _bankConnectionWatchdog = null;
        final errorCode =
            call.arguments is Map ? (call.arguments as Map)['errorCode'] : null;
        connectionStatusNotifier.value = errorCode == null
            ? 'No se pudo publicar el servidor BLE'
            : 'No se pudo publicar el servidor BLE (código $errorCode)';
        break;
    }
    return null;
  }

  void setBankMode(bool isBank) {
    _isBank = isBank;
    if (isBank) {
      connectionStatusNotifier.value = '';
    } else {
      _bankConnectionWatchdog?.cancel();
      _bankConnectionWatchdog = null;
    }
  }

  void _markClientDisconnected({String status = 'Desconectado'}) {
    _stopKeepAlive();
    _stopProximityPolling();
    _scanRefreshTimer?.cancel();
    _scanRefreshTimer = null;
    final connection = _connectSub;
    _connectSub = null;
    unawaited(connection?.cancel());
    _clientConnected = false;
    _clientCharacteristicReady = false;
    _preparingNotificationChannel = false;
    _notificationChannelPrepareAttempts = 0;
    _notificationRetryScheduled = false;
    _connectedDeviceId = null;
    _bankConnectionWatchdog?.cancel();
    _bankConnectionWatchdog = null;
    unawaited(_notifySub?.cancel());
    _notifySub = null;
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;
    clientConnectedNotifier.value = false;
    connectedDeviceNameNotifier.value = '';
    connectionStatusNotifier.value = status;
  }

  void markPlayerInactive(String deviceId) {
    _upsertConnectedPlayer(
      deviceId,
      playing: false,
      contactReady: false,
    );
  }

  void markPlayerActive(String deviceId) {
    _upsertConnectedPlayer(
      deviceId,
      playing: true,
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _audit('initialize');

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
        if (!_isBank && _clientConnected) {
          _markClientDisconnected(status: 'Bluetooth desactivado');
        } else if (_isBank) {
          _serverStarting = false;
          _serverActive = false;
          serverActiveNotifier.value = false;
          connectedPlayersNotifier.value = const [];
          clientConnectedNotifier.value = false;
          connectionStatusNotifier.value = 'Bluetooth desactivado';
        }
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
    _audit('startReceiving', data: {'isBank': _isBank});

    if (_isBank) {
      await _startBankServer();
    } else {
      await _startClientScan(onData);
    }
  }

  // ── Modo BANCO: Servidor GATT ────────────────────────────────────

  Future<void> _startBankServer() async {
    if (_serverActive || _serverStarting) return;
    _serverStarting = true;
    _audit('startBankServer');

    // Asegurar estado limpio antes de iniciar: desconectar clientes
    // y detener servidor anterior si hubiera quedado activo a nivel nativo.
    try {
      await _channel.invokeMethod('stopBleServer');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (_) {}

    serverActiveNotifier.value = false;
    connectedPlayersNotifier.value = const [];
    _bankContactSampleCounts.clear();
    _incomingChunks.clear();
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;
    connectionStatusNotifier.value = 'Iniciando servidor BLE...';

    try {
      await _channel.invokeMethod('startBleServer', {
        'serviceUuid': _serviceUuid,
        'charUuid': _charUuid,
      });
    } catch (e) {
      _serverStarting = false;
      _serverActive = false;
      serverActiveNotifier.value = false;
      connectionStatusNotifier.value = 'Error al iniciar servidor BLE';
    }
  }

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    _audit('sendPayload', data: {'type': payload['type'], 'isBank': _isBank});
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
      final frames = _encodeBleFrames(payload);
      for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
        var sent = false;
        for (var attempt = 0; attempt < 25 && !sent; attempt++) {
          sent = await _channel.invokeMethod<bool>('bleSendNotification', {
                'payload': frames[frameIndex],
              }) ??
              false;
          if (!sent) {
            final status =
                await _channel.invokeMethod<Map>('bleIsClientConnected') ?? {};
            if (status['subscribed'] != true && attempt >= 15) {
              throw TransportUnavailableException(
                'El jugador todav\u00eda no est\u00e1 listo para recibir datos por BLE.',
              );
            }
            await Future<void>.delayed(
              Duration(milliseconds: status['subscribed'] == true ? 45 : 200),
            );
          }
        }
        if (!sent) {
          throw TransportUnavailableException(
            'El canal BLE no confirmó el fragmento ${frameIndex + 1} de ${frames.length}.',
          );
        }
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
    _reconnectAllowed = true;
    _transportDisposed = false;
    _clientConnected = false;
    clientConnectedNotifier.value = false;
    connectionStatusNotifier.value = 'Buscando bancos por Bluetooth...';
    discoveredBanksNotifier.value = const [];
    _audit('startClientScan');

    final serviceUuid = Uuid.parse(_serviceUuid);

    final completer = Completer<DiscoveredDevice>();
    _pendingScanCompleter = completer;
    _scanSub = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      debugPrint(
          '[BLE client] Descubierto id=${device.id} rssi=${device.rssi}');
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

        if (!completer.isCompleted) {
          completer.complete(device);
        }
      }, onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    });

    unawaited(_awaitScanAndConnect(completer, serviceUuid));

    // Scan refresh: reinicia silenciosamente el scan cada 90s para
    // evitar que el stack BLE de Android se estanque.
    _scanRefreshTimer?.cancel();
    _scanRefreshTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      _silentRefreshScan(onData);
    });
  }

  Future<void> _silentRefreshScan(
    void Function(Map<String, dynamic>) onData,
  ) async {
    if (_transportDisposed || !_reconnectAllowed || _clientConnected) {
      _scanRefreshTimer?.cancel();
      _scanRefreshTimer = null;
      return;
    }
    _scanGeneration++;
    _audit('silent_scan_refresh');
    AppAuditLogger.instance.event('BLE_SCAN', 'silent_refresh');

    // Cancelar el scan actual
    final oldScan = _scanSub;
    final oldCompleter = _pendingScanCompleter;

    // Iniciar un scan nuevo con los mismos parámetros
    final serviceUuid = Uuid.parse(_serviceUuid);
    final completer = Completer<DiscoveredDevice>();
    _pendingScanCompleter = completer;
    _scanSub = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      debugPrint(
          '[BLE client] Descubierto id=${device.id} rssi=${device.rssi}');
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

      if (!completer.isCompleted) {
        completer.complete(device);
      }
    }, onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    });

    // Cancelar el scan viejo después de iniciar el nuevo
    await oldScan?.cancel();
    if (oldCompleter != null && !oldCompleter.isCompleted) {
      oldCompleter.completeError(StateError('Scan refreshed'));
    }

    unawaited(_awaitScanAndConnect(completer, serviceUuid));
  }

  Future<void> _awaitScanAndConnect(
      Completer<DiscoveredDevice> completer, Uuid serviceUuid) async {
    try {
      final device =
          await completer.future.timeout(const Duration(seconds: 85));
      if (_transportDisposed || !_reconnectAllowed) return;
      _scanRefreshTimer?.cancel();
      _scanRefreshTimer = null;
      await _scanSub?.cancel();
      _scanSub = null;
      _pendingScanCompleter = null;

      connectedDeviceNameNotifier.value = device.name;
      connectionStatusNotifier.value = 'Conectando a ${device.name}...';
      _connectedDeviceId = device.id;
      _connect(device.id);
    } on TimeoutException {
      _pendingScanCompleter = null;
      await _scanSub?.cancel();
      _scanSub = null;
      if (_transportDisposed || !_reconnectAllowed) return;
      debugPrint('[BLE client] No se encontró el servidor en 85 segundos');
      connectionStatusNotifier.value =
          'No se encontraron bancos. Reintentando...';
      _scheduleDelayedReconnect();
    } catch (error) {
      _pendingScanCompleter = null;
      await _scanSub?.cancel();
      _scanSub = null;
      if (_transportDisposed || !_reconnectAllowed) return;
      debugPrint('[BLE client] Error durante escaneo: $error');
      connectionStatusNotifier.value = 'Error al escanear, reintentando...';
      _scheduleDelayedReconnect();
    }
  }

  void _scheduleDelayedReconnect() {
    if (_transportDisposed || !_reconnectAllowed) return;
    final generation = _scanGeneration;
    Future.delayed(const Duration(seconds: 3), () {
      if (_transportDisposed || !_reconnectAllowed) return;
      if (generation != _scanGeneration) return;
      _reconnectScan();
    });
  }

  void _connect(String deviceId) async {
    _audit('action_connect', data: {'deviceId': deviceId});
    final serviceUuid = Uuid.parse(_serviceUuid);
    _connectSub = _ble
        .connectToAdvertisingDevice(
      id: deviceId,
      withServices: [serviceUuid],
      prescanDuration: const Duration(seconds: 2),
      connectionTimeout: const Duration(seconds: 12),
      servicesWithCharacteristicsToDiscover: {
        serviceUuid: [Uuid.parse(_charUuid)],
      },
    )
        .listen((state) {
      debugPrint('[BLE client] Estado ${deviceId}: ${state.connectionState}');
      if (state.connectionState == DeviceConnectionState.connected) {
        _clientConnected = true;
        clientConnectedNotifier.value = false;
        connectionStatusNotifier.value = 'Preparando canal de datos...';
        _prepareNotificationChannel(deviceId);
      } else if (state.connectionState ==
          DeviceConnectionState.disconnecting) {
        connectionStatusNotifier.value = 'Desconectando...';
      } else if (state.connectionState ==
          DeviceConnectionState.disconnected) {
        _markClientDisconnected(
          status: 'Conexi\u00f3n perdida. Vuelve a intentarlo.',
        );
      }
    }, onError: (Object error) {
      debugPrint('[BLE client] Error conectando ${deviceId}: $error');
      _markClientDisconnected(status: 'Error de conexi\u00f3n');
    }, onDone: () {
      debugPrint('[BLE client] Stream conexi\u00f3n ${deviceId} termin\u00f3');
      _markClientDisconnected(
        status: 'La conexi\u00f3n BLE termin\u00f3 inesperadamente.',
      );
    });
  }

  Future<void> _reconnectScan() async {
    if (_transportDisposed || !_reconnectAllowed || _isReconnecting) return;
    _isReconnecting = true;
    _audit('action_reconnect_scan');
    AppAuditLogger.instance.event('BLE_RECONNECT', 'start');
    final callback = _receiveCallback;
    await _fullStop();
    _transportDisposed = false;
    try {
      if (callback != null && _reconnectAllowed) {
        _receiveCallback = callback;
        connectionStatusNotifier.value = 'Reconectando...';
        await _startClientScan(callback);
      }
    } finally {
      _isReconnecting = false;
    }
  }

  Future<void> connectToBank(BleBankDevice bank) async {
    _isBank = false;
    _reconnectAllowed = true;
    _audit('connectToBank',
        data: {'bankId': bank.id, 'bankName': bank.name, 'rssi': bank.rssi});
    final savedBanks = [...discoveredBanksNotifier.value];
    final savedCallback = _receiveCallback;
    await _fullStop();
    _transportDisposed = false;
    _reconnectAllowed = true;
    _receiveCallback = savedCallback;
    discoveredBanksNotifier.value = savedBanks;
    await _scanSub?.cancel();
    _scanSub = null;
    await _connectSub?.cancel();
    _connectSub = null;
    await _notifySub?.cancel();
    _notifySub = null;

    _clientConnected = false;
    _clientCharacteristicReady = false;
    _preparingNotificationChannel = false;
    clientConnectedNotifier.value = false;
    connectedDeviceNameNotifier.value = bank.name;
    connectionStatusNotifier.value = 'Conectando a ${bank.name}...';
    _connectedDeviceId = bank.id;

    _connect(bank.id);
  }

  void _subscribeToNotifications() {
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return;

    _notifySub?.cancel();
    _notifySub = _ble
        .subscribeToCharacteristic(
      QualifiedCharacteristic(
        serviceId: Uuid.parse(_serviceUuid),
        characteristicId: Uuid.parse(_charUuid),
        deviceId: deviceId,
      ),
    )
        .listen((bytes) {
      try {
        final jsonStr = utf8.decode(bytes);
        if (jsonStr.contains('"type":"pong"')) {
          _lastPongReceived = DateTime.now();
          _pongMissedCount = 0;
          return;
        }
        final data = _decodeBleFrame(jsonStr);
        if (data == null) return;
        _startKeepAlive(deviceId);
        _startProximityPolling();
        clientConnectedNotifier.value = true;
        _notificationRetryScheduled = false;
        connectionStatusNotifier.value = 'Conectado al banco';
        _receiveCallback?.call(data);
      } catch (_) {}
    }, onError: (error) {
      debugPrint('[BLE client] Error en suscripción $deviceId: $error');
      AppAuditLogger.instance.event(
        'BLE_SUBSCRIPTION',
        'Falló la suscripción a $deviceId',
        error: error,
      );
      if (!_clientConnected || _connectedDeviceId != deviceId) return;
      contactReadyNotifier.value = false;
      contactRssiNotifier.value = null;
      clientConnectedNotifier.value = false;
      connectionStatusNotifier.value =
          'Conectado al banco. Restableciendo canal de datos...';
      if (_notificationRetryScheduled) return;
      _notificationRetryScheduled = true;
      Future.delayed(const Duration(seconds: 2), () {
        _notificationRetryScheduled = false;
        if (!_transportDisposed &&
            _clientConnected &&
            _connectedDeviceId == deviceId) {
          _subscribeToNotifications();
        }
      });
    });
  }

  int _notificationChannelPrepareAttempts = 0;

  Future<void> _prepareNotificationChannel(String deviceId) async {
    if (_preparingNotificationChannel) return;
    _preparingNotificationChannel = true;
    try {
      final characteristicReady = await _discoverClientCharacteristic(deviceId);
      if (!characteristicReady) {
        if (_clientConnected && _connectedDeviceId == deviceId) {
          _notificationChannelPrepareAttempts += 1;
          _audit('prepareNotificationChannel_retry', data: {'attempt': _notificationChannelPrepareAttempts});
          if (_notificationChannelPrepareAttempts >= 2) {
            _notificationChannelPrepareAttempts = 0;
            _logConnection('No se pudo descubrir el canal BLE. Forzando reconexión...');
            _audit('prepareNotificationChannel_force_reconnect');
            _forceClientReconnect(deviceId);
            return;
          }
          connectionStatusNotifier.value =
              'Esperando que Android descubra el canal BLE...';
          Future<void>.delayed(const Duration(seconds: 1), () {
            if (!_transportDisposed &&
                _clientConnected &&
                _connectedDeviceId == deviceId) {
              _prepareNotificationChannel(deviceId);
            }
          });
        }
        return;
      }
      _notificationChannelPrepareAttempts = 0;
      _audit('prepareNotificationChannel_ready');

      try {
        await _ble.requestMtu(deviceId: deviceId, mtu: 247);
        debugPrint('[BLE client] MTU preparado para $deviceId');
      } catch (error) {
        debugPrint('[BLE client] No se pudo negociar MTU: $error');
      }

      if (!_clientConnected || _connectedDeviceId != deviceId) return;
      clientConnectedNotifier.value = false;
      connectionStatusNotifier.value = 'Preparando canal de datos...';
      _subscribeToNotifications();
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        _sendIdentityOnce();
      });
    } finally {
      _preparingNotificationChannel = false;
    }
  }

  void _forceClientReconnect(String deviceId) {
    if (_connectedDeviceId != deviceId) return;
    _markClientDisconnected(status: 'Reconectando por fallo de descubrimiento...');
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (_transportDisposed || !_reconnectAllowed || _receiveCallback == null) {
        return;
      }
      _reconnectScan();
    });
  }

  void _logConnection(String message) {
    debugPrint('[BLE client] $message');
    AppAuditLogger.instance.event('BLE_CONNECTION', message);
  }

  Future<bool> _discoverClientCharacteristic(String deviceId) async {
    final serviceUuid = Uuid.parse(_serviceUuid);
    final characteristicUuid = Uuid.parse(_charUuid);
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (!_clientConnected || _connectedDeviceId != deviceId) return false;
      try {
        await _ble
            .discoverAllServices(deviceId)
            .timeout(const Duration(seconds: 4));
        final services = await _ble
            .getDiscoveredServices(deviceId)
            .timeout(const Duration(seconds: 4));
        final found = services.any(
          (service) =>
              service.id == serviceUuid &&
              service.characteristics.any(
                  (characteristic) => characteristic.id == characteristicUuid),
        );
        if (found) {
          _clientCharacteristicReady = true;
          debugPrint('[BLE client] Característica GATT descubierta');
          return true;
        }
        debugPrint('[BLE client] Característica no encontrada en intento $attempt');
      } catch (error) {
        debugPrint(
            '[BLE client] Descubrimiento GATT intento $attempt falló: $error');
        AppAuditLogger.instance.event(
          'BLE_DISCOVERY',
          'Intento $attempt de descubrimiento GATT para $deviceId',
          error: error,
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
    _clientCharacteristicReady = false;
    return false;
  }

  void _startKeepAlive(String deviceId) {
    _keepAliveTimer?.cancel();
    _lastPongReceived = DateTime.now();
    _pongMissedCount = 0;
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_clientConnected || _connectedDeviceId != deviceId) {
        _keepAliveTimer?.cancel();
        _keepAliveTimer = null;
        return;
      }
      final lastAck = _lastPongReceived;
      if (lastAck != null &&
          DateTime.now().difference(lastAck) > const Duration(seconds: 5)) {
        _pongMissedCount += 1;
        _logConnection(
            'No se recibe keepalive_ack desde hace 5s (fallo $_pongMissedCount)');
        if (_pongMissedCount >= 4) {
          _logConnection(
              'Conexión perdida por falta de keepalive_ack ($_pongMissedCount fallos). Reconectando...');
          AppAuditLogger.instance.event(
            'BLE_KEEPALIVE',
            'reconnect_after_missed_pongs',
            data: {'missedCount': _pongMissedCount},
          );
          _keepAliveTimer?.cancel();
          _keepAliveTimer = null;
          _markClientDisconnected(status: 'Conexión BLE perdida');
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (!_transportDisposed &&
                _reconnectAllowed &&
                _receiveCallback != null) {
              _reconnectScan();
            }
          });
          return;
        }
      }
      try {
        await _ble.writeCharacteristicWithResponse(
          QualifiedCharacteristic(
            serviceId: Uuid.parse(_serviceUuid),
            characteristicId: Uuid.parse(_charUuid),
            deviceId: deviceId,
          ),
          value: utf8.encode('{"type":"ping"}'),
        );
      } catch (error) {
        _logConnection('No se pudo enviar ping keepalive: $error');
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _lastPongReceived = null;
    _pongMissedCount = 0;
  }

  void _startProximityPolling() {
    _stopProximityPolling();
    _proximityPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final deviceId = _connectedDeviceId;
      if (!_clientConnected || deviceId == null || _transportDisposed) {
        _stopProximityPolling();
        return;
      }
      try {
        final rssi = await _ble.readRssi(deviceId).timeout(
              const Duration(seconds: 3),
              onTimeout: () => throw TimeoutException('readRssi timeout'),
            );
        await _writeClientPayload({
          'type': 'ble_proximity',
          'rssi': rssi,
        });
      } catch (e) {
        debugPrint('[BLE proximity] Error leyendo/enviando RSSI: $e');
      }
    });
  }

  void _stopProximityPolling() {
    _proximityPollTimer?.cancel();
    _proximityPollTimer = null;
  }

  Future<void> _sendViaClient(Map<String, dynamic> payload) async {
    try {
      await _writeClientPayload(payload);
    } catch (e) {
      _markClientDisconnected(status: 'Conexión con el banco perdida');
      throw TransportUnavailableException('Error al enviar: $e');
    }
  }

  Future<void> _writeClientPayload(Map<String, dynamic> payload) async {
    final operation = _clientWriteChain.catchError((_) {}).then((_) async {
      final deviceId = _connectedDeviceId;
      if (!_clientConnected || deviceId == null) {
        throw TransportUnavailableException('No hay conexi\u00f3n al banco');
      }
      if (!_clientCharacteristicReady &&
          !await _discoverClientCharacteristic(deviceId)) {
        throw TransportUnavailableException(
            'La característica BLE todavía no fue descubierta');
      }

      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(_serviceUuid),
        characteristicId: Uuid.parse(_charUuid),
        deviceId: deviceId,
      );

      final frames = _encodeBleFrames(payload);
      for (final frame in frames) {
        await _ble
            .writeCharacteristicWithResponse(
              characteristic,
              value: utf8.encode(frame),
            )
            .timeout(const Duration(seconds: 3));
      }
    });
    _clientWriteChain = operation.catchError((_) {});
    try {
      await operation;
    } catch (error, stack) {
      AppAuditLogger.instance.event(
        'BLE_WRITE',
        'Falló el envío de payload tipo ${payload['type']}',
        error: error,
        stack: stack,
      );
      rethrow;
    }
  }

  Future<void> startServer() async {
    _isBank = true;
    if (_serverActive) return;
    await _fullStop();
    await _checkBatteryOptimizationAndKeepScreenOn();
    await refreshAvailability();
    if (!isEnabled) {
      throw TransportUnavailableException('Bluetooth no est\u00e1 disponible');
    }
    await _startBankServer();
  }

  Future<void> stopServer() async {
    if (!_isBank) return;
    if (_serverActive && clientConnectedNotifier.value) {
      try {
        await _sendViaServer({
          'type': 'bank_server_stopping',
          'reason': 'server_stopped_by_bank',
        });
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        // El callback de desconexión sigue funcionando como respaldo.
      }
    }
    await stop();
  }

  Future<void> startClientScan(
      void Function(Map<String, dynamic>) onData) async {
    _isBank = false;
    await _fullStop();
    await _startClientScan(onData);
  }

  Future<void> stopClientScan() async {
    if (_isBank) return;
    await stop();
  }

  @override
  Future<void> stop() async {
    _audit('stop');
    _transportDisposed = true;
    _receiveCallback = null;
    _reconnectAllowed = false;
    _notificationRetryScheduled = false;
    _serverStarting = false;
    _stopKeepAlive();
    _stopProximityPolling();
    _scanRefreshTimer?.cancel();
    _scanRefreshTimer = null;
    _clientConnected = false;
    _clientCharacteristicReady = false;
    _preparingNotificationChannel = false;
    _notificationChannelPrepareAttempts = 0;
    _connectedDeviceId = null;

    final pendingCompleter = _pendingScanCompleter;
    _pendingScanCompleter = null;
    if (pendingCompleter != null && !pendingCompleter.isCompleted) {
      pendingCompleter.completeError(
        StateError('Transport detenido'),
      );
    }

    clientConnectedNotifier.value = false;
    connectedDeviceNameNotifier.value = '';
    connectionStatusNotifier.value = '';
    discoveredBanksNotifier.value = const [];
    connectedPlayersNotifier.value = const [];
    _bankContactSampleCounts.clear();
    contactReadyNotifier.value = false;
    contactRssiNotifier.value = null;

    await _scanSub?.cancel();
    _scanSub = null;
    await _connectSub?.cancel();
    _connectSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
    if (_isBank) {
      _serverActive = false;
      serverActiveNotifier.value = false;
      connectionStatusNotifier.value = '';
      try {
        await _channel.invokeMethod('stopBleServer');
        await _channel.invokeMethod('keepScreenOn', {'keepOn': false});
      } catch (_) {}
    }
  }

  Future<void> _fullStop() async {
    _audit('action_full_stop');
    final previousDeviceId = _connectedDeviceId;
    await stop();
    if (previousDeviceId != null) {
      await _clearBleCacheForDevice(previousDeviceId);
    }
    // Dar tiempo al stack BLE de Android para liberar el rol anterior.
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _clearBleCacheForDevice(String deviceId) async {
    _audit('action_clear_ble_cache', data: {'deviceId': deviceId});
    try {
      await _channel.invokeMethod<bool>('bleUnbondDevice', {'deviceId': deviceId});
    } catch (_) {}
    try {
      await _channel.invokeMethod<bool>('bleRefreshDeviceCache', {'deviceId': deviceId});
    } catch (_) {}
  }

  Future<void> disconnectClient(String deviceId) async {
    _audit('disconnectClient', data: {'deviceId': deviceId});
    _removeConnectedPlayer(deviceId);
    await _channel.invokeMethod<bool>('bleDisconnectClient',
        {'deviceId': deviceId});
    await _clearBleCacheForDevice(deviceId);
  }

  Future<void> resetState() async {
    _audit('resetState');
    await stop();
    try {
      await _channel.invokeMethod<void>('bleResetState');
      AppAuditLogger.instance.event('BLE_RESET', 'Estado nativo limpiado');
    } catch (error, stack) {
      AppAuditLogger.instance.event(
        'BLE_RESET_ERROR',
        'No se pudo limpiar estado nativo',
        error: error,
        stack: stack,
      );
    }
  }

  Future<bool> restartBluetooth() async {
    _audit('restartBluetooth');
    await stop();
    try {
      final ok = await _channel.invokeMethod<bool>('bleRestartBluetooth') ?? false;
      AppAuditLogger.instance.event(
        'BLE_BT_RESTART',
        ok ? 'Bluetooth reiniciado' : 'Falló reinicio Bluetooth',
      );
      return ok;
    } catch (error, stack) {
      AppAuditLogger.instance.event(
        'BLE_BT_RESTART_ERROR',
        'Error reiniciando Bluetooth',
        error: error,
        stack: stack,
      );
      return false;
    }
  }

  @override
  void dispose() {
    _stopKeepAlive();
    _scanRefreshTimer?.cancel();
    _scanRefreshTimer = null;
    _scanSub?.cancel();
    _connectSub?.cancel();
    _notifySub?.cancel();
    _receiveCallback = null;
    discoveredBanksNotifier.dispose();
    connectedPlayersNotifier.dispose();
    contactReadyNotifier.dispose();
    contactRssiNotifier.dispose();
    contactProfileIndexNotifier.dispose();
    _channel.setMethodCallHandler(null);
  }
}
