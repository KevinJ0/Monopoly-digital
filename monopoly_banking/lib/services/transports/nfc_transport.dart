import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';

class NfcDisabledException implements Exception {
  const NfcDisabledException();
}

class NfcTransport extends P2PTransport {
  @override
  String get name => 'NFC';

  @override
  IconData get icon => Icons.nfc_rounded;

  @override
  String get description => 'Acerca los teléfonos para transferir';

  @override
  bool get isEnabled => _availability == NfcAvailability.enabled;

  static const _channel = MethodChannel('com.monopoly/nfc');

  NfcAvailability _availability = NfcAvailability.unsupported;
  bool _sessionActive = false;
  bool _processing = false;
  Completer<void>? _sessionCompleter;

  @override
  Future<void> initialize() async {
    _availability = await checkAvailability();
  }

  Future<NfcAvailability> checkAvailability() async {
    // En Android consultamos primero el adaptador nativo. Algunos fabricantes
    // devuelven `unsupported` temporalmente desde nfc_manager aunque el
    // adaptador y HCE estén disponibles.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final hasHardware =
            await _channel.invokeMethod<bool>('hasNfcHardware') ?? false;
        if (hasHardware) {
          final isEnabled =
              await _channel.invokeMethod<bool>('isNfcEnabled') ?? false;
          _availability =
              isEnabled ? NfcAvailability.enabled : NfcAvailability.disabled;
          return _availability;
        }
      } catch (_) {
        // Si el canal nativo todavía no está listo, usamos el plugin.
      }
    }

    try {
      final result = await NfcManager.instance.checkAvailability();
      if (result != NfcAvailability.unsupported) {
        _availability = result;
        return result;
      }
    } catch (_) {}

    try {
      final hasHardware =
          await _channel.invokeMethod<bool>('hasNfcHardware') ?? false;
      if (!hasHardware) {
        _availability = NfcAvailability.unsupported;
        return _availability;
      }
      final isEnabled =
          await _channel.invokeMethod<bool>('isNfcEnabled') ?? false;
      _availability =
          isEnabled ? NfcAvailability.enabled : NfcAvailability.disabled;
      return _availability;
    } catch (_) {
      return _availability;
    }
  }

  Future<void> openNfcSettings() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<void>('openNfcSettings');
      } catch (_) {}
    }
  }

  @override
  Future<void> startReceiving(
      void Function(Map<String, dynamic>) onData) async {
    if (_sessionActive) await stop();
    _sessionActive = true;

    final completer = Completer<void>();
    _sessionCompleter = completer;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (_processing) return;
          _processing = true;
          try {
            await _handleDiscoveredTag(tag, onData);
          } finally {
            _processing = false;
          }
        },
      );

      await completer.future;
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    } finally {
      _sessionActive = false;
      _sessionCompleter = null;
    }
  }

  Future<void> _handleDiscoveredTag(
      NfcTag tag, void Function(Map<String, dynamic>) onData) async {
    try {
      final isoDep = IsoDepAndroid.from(tag);
      if (isoDep != null) {
        await _handleIsoDep(isoDep, onData);
        return;
      }
      await _handleNdef(tag, onData);
    } finally {
      if (_sessionActive) await _stopSessionInternal();
    }
  }

  Future<void> _handleIsoDep(
      IsoDepAndroid isoDep, void Function(Map<String, dynamic>) onData) async {
    try {
      final selectAid = Uint8List.fromList([
        0x00,
        0xA4,
        0x04,
        0x00,
        0x09,
        0xF0,
        0x4D,
        0x4F,
        0x4E,
        0x4F,
        0x50,
        0x4F,
        0x4C,
        0x59,
        0x00,
      ]);
      final selectResp = await isoDep.transceive(selectAid);
      if (selectResp.length < 2 ||
          selectResp[selectResp.length - 2] != 0x90 ||
          selectResp[selectResp.length - 1] != 0x00) {
        return;
      }

      final dataResp = await isoDep.transceive(
        Uint8List.fromList([0x00, 0xCA, 0x00, 0x00, 0x00]),
      );
      if (dataResp.length < 4) return;
      final payloadLen = (dataResp[0] << 8) | dataResp[1];
      if (dataResp.length < 2 + payloadLen + 2) return;
      final jsonStr = utf8.decode(dataResp.sublist(2, 2 + payloadLen));
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      onData(data);
    } catch (_) {}
  }

  Future<void> _handleNdef(
      NfcTag tag, void Function(Map<String, dynamic>) onData) async {
    try {
      final ndefAndroid = NdefAndroid.from(tag);
      final cached = ndefAndroid?.cachedNdefMessage;
      if (cached == null || cached.records.isEmpty) return;
      final raw = cached.records.first.payload;
      final jsonStr = utf8.decode(raw.skip(3).toList());
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      onData(data);
    } catch (_) {}
  }

  Future<void> _stopSessionInternal() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    await NfcManager.instance.stopSession();
    if (_sessionCompleter != null && !_sessionCompleter!.isCompleted) {
      _sessionCompleter!.complete();
    }
    _sessionCompleter = null;
  }

  Timer? _hceAutoStopTimer;

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    _hceAutoStopTimer?.cancel();
    await _stopSessionInternal();
    await stopHce();
    await startHce(payload);
    _hceAutoStopTimer = Timer(const Duration(seconds: 8), () {
      stopHce();
      _hceAutoStopTimer = null;
    });
  }

  Future<void> startHce(Map<String, dynamic> payload) async {
    final jsonStr = jsonEncode(payload);
    await _channel.invokeMethod<void>('hceStart', {'payload': jsonStr});
  }

  Future<void> stopHce() async {
    await _channel.invokeMethod<void>('hceStop');
  }

  @override
  Future<void> stop() async {
    _hceAutoStopTimer?.cancel();
    _hceAutoStopTimer = null;
    await _stopSessionInternal();
    await stopHce();
  }

  @override
  void dispose() {
    _hceAutoStopTimer?.cancel();
    _hceAutoStopTimer = null;
  }
}
