import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/nfc_transport.dart';
import 'package:monopoly_banking/services/transports/ble_transport.dart';
import 'package:monopoly_banking/services/transports/wifi_transport.dart';

export 'package:monopoly_banking/services/transports/nfc_transport.dart'
    show NfcDisabledException;

typedef P2PPayloadHandler = void Function(Map<String, dynamic> payload);

enum TransportType { nfc, ble, wifi }

class P2PService {
  static final P2PService _instance = P2PService._();
  factory P2PService() => _instance;
  P2PService._();

  final nfcTransport = NfcTransport();
  final bleTransport = BleTransport();
  final wifiTransport = WifiTransport();

  final _payloadStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get payloadStream => _payloadStreamCtrl.stream;

  P2PTransport get _active => transports[_currentType]!;

  final Map<TransportType, P2PTransport> transports = {};

  TransportType _currentType = TransportType.nfc;
  TransportType get currentType => _currentType;

  final _typeCtrl = ValueNotifier<TransportType>(TransportType.nfc);
  ValueNotifier<TransportType> get typeNotifier => _typeCtrl;

  int _txCounter = 0;

  Future<void> initTransports({bool isBank = false}) async {
    bleTransport.setBankMode(isBank);

    transports[TransportType.nfc] = nfcTransport;
    transports[TransportType.ble] = bleTransport;
    transports[TransportType.wifi] = wifiTransport;

    await nfcTransport.initialize();
    await bleTransport.initialize();
    await wifiTransport.initialize();
  }

  void setTransport(TransportType type) {
    _currentType = type;
    _typeCtrl.value = type;
  }

  Future<void> startReceiving(P2PPayloadHandler? legacyHandler) async {
    if (legacyHandler != null) {
      _payloadStreamCtrl.stream.listen(legacyHandler);
    }

    final transport = _active;
    if (!transport.isEnabled) return;

    await transport.startReceiving((payload) {
      _payloadStreamCtrl.add(payload);
    });
  }

  Future<void> sendPayload(Map<String, dynamic> payload) async {
    _txCounter++;
    payload['txId'] = '${DateTime.now().millisecondsSinceEpoch}-$_txCounter';

    final transport = _active;
    if (!transport.isEnabled) {
      if (_currentType == TransportType.ble) {
        throw TransportUnavailableException('Bluetooth no está disponible');
      }
      for (final entry in transports.entries) {
        if (entry.value.isEnabled) {
          await entry.value.sendPayload(payload);
          return;
        }
      }
      throw TransportUnavailableException('No hay transporte disponible');
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
    for (final transport in transports.values) {
      await transport.stop();
    }
  }

  void dispose() {
    for (final transport in transports.values) {
      transport.dispose();
    }
    _payloadStreamCtrl.close();
    _typeCtrl.dispose();
  }
}
