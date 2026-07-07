import 'dart:async';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

typedef BlePayloadHandler = void Function(Map<String, dynamic> payload);

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  static const String _serviceUuidBase = '12345678-0000-1000-8000-';
  static const String _charUuid = '12345678-0001-1000-8000-00805f9b34fb';

  final _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectSub;
  StreamSubscription<List<int>>? _notifySub;

  String? _gameId;
  String? _connectedDeviceId;

  Uuid _buildServiceUuid(String gameId) {
    final suffix = gameId.substring(0, 12).padRight(12, '0');
    return Uuid.parse('$_serviceUuidBase$suffix');
  }

  Future<void> startAdvertising(String gameId) async {
    _gameId = gameId;
  }

  Future<void> scanAndConnect(
      String gameId, BlePayloadHandler onPayload) async {
    _gameId = gameId;
    final serviceUuid = _buildServiceUuid(gameId);

    _scanSub = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) async {
      await _scanSub?.cancel();
      _connectToDevice(device.id, serviceUuid, onPayload);
    });
  }

  void _connectToDevice(
    String deviceId,
    Uuid serviceUuid,
    BlePayloadHandler onPayload,
  ) {
    _connectSub = _ble.connectToDevice(id: deviceId).listen((state) {
      if (state.connectionState == DeviceConnectionState.connected) {
        _connectedDeviceId = deviceId;
        _subscribeToCharacteristic(deviceId, serviceUuid, onPayload);
      }
    });
  }

  void _subscribeToCharacteristic(
    String deviceId,
    Uuid serviceUuid,
    BlePayloadHandler onPayload,
  ) {
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: Uuid.parse(_charUuid),
      deviceId: deviceId,
    );

    _notifySub = _ble.subscribeToCharacteristic(characteristic).listen((bytes) {
      try {
        final jsonStr = utf8.decode(bytes);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        onPayload(data);
      } catch (_) {}
    });
  }

  Future<void> writePayload(Map<String, dynamic> payload) async {
    if (_connectedDeviceId == null || _gameId == null) return;

    final serviceUuid = _buildServiceUuid(_gameId!);
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: Uuid.parse(_charUuid),
      deviceId: _connectedDeviceId!,
    );

    final bytes = utf8.encode(jsonEncode(payload));
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: bytes,
    );
  }

  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _connectSub?.cancel();
    await _notifySub?.cancel();
    _connectedDeviceId = null;
    _gameId = null;
  }
}
