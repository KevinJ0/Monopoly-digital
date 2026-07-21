import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/ws_transport.dart';
import 'package:monopoly_banking/services/transports/wifi_transport.dart';

typedef P2PPayloadHandler = void Function(Map<String, dynamic> payload);

enum TransportType { ws, wifi }

class P2PService {
  static const _transportSettingKey = 'connection_transport';
  static final P2PService _instance = P2PService._();
  factory P2PService() => _instance;
  P2PService._();

  final wsTransport = WsTransport();
  final wifiTransport = WifiTransport();

  final _payloadStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get payloadStream => _payloadStreamCtrl.stream;
  StreamSubscription<Map<String, dynamic>>? _legacyPayloadSub;

  P2PTransport get _active {
    final transport = transports[_currentType];
    if (transport == null) {
      debugPrint('P2PService: transport $_currentType not registered, falling back to ws');
      return transports[TransportType.ws]!;
    }
    return transport;
  }

  final Map<TransportType, P2PTransport> transports = {};

  TransportType _currentType = TransportType.ws;
  TransportType get currentType => _currentType;

  final _typeCtrl = ValueNotifier<TransportType>(TransportType.ws);
  ValueNotifier<TransportType> get typeNotifier => _typeCtrl;

  int _txCounter = 0;

  Future<void> initTransports({bool isBank = false}) async {
    wsTransport.setBankMode(isBank);

    transports[TransportType.ws] = wsTransport;
    transports[TransportType.wifi] = wifiTransport;

    final savedTransport = HiveService.settingsBox.get(_transportSettingKey);
    if (savedTransport is String) {
      for (final type in TransportType.values) {
        if (type.name == savedTransport) {
          _currentType = type;
          _typeCtrl.value = type;
          break;
        }
      }
    }

    await wsTransport.initialize();
    await wifiTransport.initialize();
  }

  void setTransport(TransportType type) {
    if (!transports.containsKey(type)) {
      debugPrint('P2PService: cannot set transport $type, not registered');
      return;
    }
    _currentType = type;
    _typeCtrl.value = type;
    unawaited(HiveService.settingsBox.put(_transportSettingKey, type.name));
  }

  Future<void> startReceiving(P2PPayloadHandler? legacyHandler) async {
    if (legacyHandler != null) {
      await _legacyPayloadSub?.cancel();
      _legacyPayloadSub = _payloadStreamCtrl.stream.listen(legacyHandler);
    }

    final transport = _active;
    if (!transport.isEnabled) return;

    await transport.startReceiving((payload) {
      _payloadStreamCtrl.add(payload);
    });
  }

  Future<void> startWsServer() async {
    wsTransport.setBankMode(true);
    if (!wsTransport.isEnabled) return;
    await wsTransport.startReceiving((payload) {
      _payloadStreamCtrl.add(payload);
    });
  }

  Future<void> sendPayload(Map<String, dynamic> payload) async {
    _txCounter++;
    payload['txId'] = '${DateTime.now().millisecondsSinceEpoch}-$_txCounter';

    final transport = _active;
    if (!transport.isEnabled) {
      throw TransportUnavailableException('${transport.name} no está disponible');
    }
    await transport.sendPayload(payload);
  }

  Future<void> sendHandshake({
    required double initialBalance,
    required String avatarId,
    required String colorId,
    required String gameId,
    String? name,
  }) async {
    final payload = {
      'type': 'handshake',
      'balance': initialBalance,
      'avatarId': avatarId,
      'colorId': colorId,
      'gameId': gameId,
      'name': name,
    };
    await sendPayload(payload);
  }

  Future<void> shutdown() async {
    await _legacyPayloadSub?.cancel();
    _legacyPayloadSub = null;
    for (final transport in transports.values) {
      await transport.stop();
    }
  }

  void dispose() {
    _legacyPayloadSub?.cancel();
    for (final transport in transports.values) {
      transport.dispose();
    }
    _payloadStreamCtrl.close();
    _typeCtrl.dispose();
  }
}
