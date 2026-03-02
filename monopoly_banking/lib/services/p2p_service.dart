import 'dart:async';
import 'package:monopoly_banking/services/ble_service.dart';
import 'package:monopoly_banking/services/nfc_service.dart';

typedef P2PPayloadHandler = void Function(Map<String, dynamic> payload);

class P2PService {
  static final P2PService _instance = P2PService._();
  factory P2PService() => _instance;
  P2PService._();

  final _nfc = NfcService();
  final _ble = BleService();

  final _payloadStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get payloadStream => _payloadStreamCtrl.stream;

  bool _isListening = false;

  Future<void> startReceiving(P2PPayloadHandler? legacyHandler) async {
    if (legacyHandler != null) {
      _payloadStreamCtrl.stream.listen(legacyHandler);
    }

    if (_isListening) return;
    _isListening = true;

    final nfcAvailable = await _nfc.isAvailable;
    if (nfcAvailable) {
      await _nfc.startReader((payload) {
        _payloadStreamCtrl.add(payload);
      });
    } else {
      await _ble.scanAndConnect('monopoly', (payload) {
        _payloadStreamCtrl.add(payload);
      });
    }
  }

  Future<void> sendPayload(Map<String, dynamic> payload) async {
    final nfcAvailable = await _nfc.isAvailable;
    if (nfcAvailable) {
      await _nfc.startWriter(payload);
    } else {
      await _ble.writePayload(payload);
    }
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
    _isListening = false;
    await _nfc.stopSession();
    await _ble.dispose();
  }
}
