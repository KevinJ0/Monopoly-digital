import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:nfc_manager/ndef_record.dart';

typedef NfcPayloadHandler = void Function(Map<String, dynamic> payload);

class NfcService {
  static final NfcService _instance = NfcService._();
  factory NfcService() => _instance;
  NfcService._();

  bool _sessionActive = false;

  Future<bool> get isAvailable async => (await NfcManager.instance.checkAvailability()) == NfcAvailability.enabled;

  Future<void> startReader(NfcPayloadHandler onPayload) async {
    if (_sessionActive) return;
    _sessionActive = true;

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        final ndefAndroid = NdefAndroid.from(tag);
        final ndefIos = NdefIos.from(tag);
        final cached = ndefAndroid?.cachedNdefMessage ?? ndefIos?.cachedNdefMessage;

        if (cached == null || cached.records.isEmpty) return;

        final raw = cached.records.first.payload;
        // Skip language code (e.g. 3 bytes for 'en')
        final jsonStr = utf8.decode(raw.skip(3).toList());
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          onPayload(data);
        } catch (_) {}
      },
    );
  }

  Future<void> writeTag(NfcTag tag, Map<String, dynamic> payload) async {
    final ndefAndroid = NdefAndroid.from(tag);
    final ndefIos = NdefIos.from(tag);

    if (ndefAndroid == null && ndefIos == null) return;

    final bytes = utf8.encode(jsonEncode(payload));
    final record = NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x54]), // 'T' for Text
      identifier: Uint8List(0),
      payload: Uint8List.fromList([0x02, 0x65, 0x6E, ...bytes]),
    );

    final message = NdefMessage(records: [record]);

    if (ndefAndroid != null) {
      if (!ndefAndroid.isWritable) return;
      await ndefAndroid.writeNdefMessage(message);
    } else if (ndefIos != null) {
      if (ndefIos.status != NdefStatusIos.readWrite) return;
      await ndefIos.writeNdef(message);
    }
  }

  Future<void> startWriter(Map<String, dynamic> payload) async {
    if (_sessionActive) return;
    _sessionActive = true;

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        await writeTag(tag, payload);
        await stopSession();
      },
    );
  }

  Future<void> stopSession() async {
    _sessionActive = false;
    await NfcManager.instance.stopSession();
  }
}
