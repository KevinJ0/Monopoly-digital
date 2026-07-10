import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

/// Resultado de leer un tag NFC.
class NfcLibTagResult {
  final String? id;
  final String? techList;
  final String? selectApduHex;
  final String? payload;
  final String? ndefPayload;
  final String? error;

  const NfcLibTagResult({
    this.id,
    this.techList,
    this.selectApduHex,
    this.payload,
    this.ndefPayload,
    this.error,
  });

  bool get isSuccess => error == null && (payload != null || ndefPayload != null);
}

/// Librería reutilizable de operaciones NFC: escanear tags, emular HCE,
/// verificar disponibilidad. Separada de la UI para poder reutilizarse
/// en cualquier pantalla o test.
class NfcLib {
  static const _channel = MethodChannel('com.monopoly/nfc');
  static final NfcLib instance = NfcLib._();
  NfcLib._();

  bool _processing = false;

  /// Verifica si NFC está disponible en el dispositivo.
  Future<NfcAvailability> checkAvailability() async {
    try {
      final hasHardware = await _channel.invokeMethod<bool>('hasNfcHardware') ?? false;
      if (hasHardware) {
        final isEnabled = await _channel.invokeMethod<bool>('isNfcEnabled') ?? false;
        return isEnabled ? NfcAvailability.enabled : NfcAvailability.disabled;
      }
    } catch (_) {}

    try {
      final result = await NfcManager.instance.checkAvailability();
      if (result != NfcAvailability.unsupported) return result;
    } catch (_) {}

    try {
      final hasHardware = await _channel.invokeMethod<bool>('hasNfcHardware') ?? false;
      if (!hasHardware) return NfcAvailability.unsupported;
      final isEnabled = await _channel.invokeMethod<bool>('isNfcEnabled') ?? false;
      return isEnabled ? NfcAvailability.enabled : NfcAvailability.disabled;
    } catch (_) {
      return NfcAvailability.unsupported;
    }
  }

  /// Abre los ajustes NFC del sistema.
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openNfcSettings');
    } catch (_) {
      try {
        await _channel.invokeMethod<void>('openNfcSettings');
      } catch (_) {}
    }
  }

  /// Inicia una sesión NFC en modo lector.
  /// Llama [onTag] cada vez que se detecta un tag.
  /// Llama [onError] si la sesión falla.
  Future<void> startScan({
    required void Function(NfcLibTagResult tag) onTag,
    void Function(Object error, StackTrace stack)? onError,
    Set<NfcPollingOption> pollingOptions = const {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
  }) async {
    _processing = false;
    return NfcManager.instance.startSession(
      pollingOptions: pollingOptions,
      onDiscovered: (NfcTag tag) async {
        if (_processing) return;
        _processing = true;
        try {
          final result = await _readTag(tag);
          onTag(result);
        } finally {
          await Future.delayed(const Duration(milliseconds: 800));
          _processing = false;
        }
      },
    );
  }

  /// Detiene la sesión NFC activa.
  Future<void> stopScan() async {
    _processing = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  /// Activa HCE (Host Card Emulation) con el payload dado.
  Future<void> startHce(Map<String, dynamic> payload) async {
    final jsonStr = jsonEncode(payload);
    await _channel.invokeMethod<void>('hceStart', {'payload': jsonStr});
  }

  /// Detiene el HCE activo.
  Future<void> stopHce() async {
    await _channel.invokeMethod<void>('hceStop');
  }

  /// Lee un tag NFC detectado.
  Future<NfcLibTagResult> _readTag(NfcTag tag) async {
    // Intentar IsoDep/HCE primero
    final isoDep = IsoDepAndroid.from(tag);
    if (isoDep != null) {
      return _readIsoDep(isoDep, tag);
    }

    // Fallback: NDEF pasivo
    return _readNdef(tag);
  }

  Future<NfcLibTagResult> _readIsoDep(IsoDepAndroid isoDep, NfcTag tag) async {
    final tagAndroid = NfcTagAndroid.from(tag);
    String? idHex;
    String? techs;
    if (tagAndroid != null) {
      idHex = tagAndroid.id
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
      techs = tagAndroid.techList.join(', ');
    }

    try {
      final selectAid = Uint8List.fromList([
        0x00, 0xA4, 0x04, 0x00, 0x09,
        0xF0, 0x4D, 0x4F, 0x4E, 0x4F, 0x50, 0x4F, 0x4C, 0x59, 0x00,
      ]);
      final selectResp = await isoDep.transceive(selectAid);
      final selectHex = selectResp
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();

      final apduOk = selectResp.length >= 2 &&
          selectResp[selectResp.length - 2] == 0x90 &&
          selectResp[selectResp.length - 1] == 0x00;

      if (apduOk) {
        final dataResp = await isoDep.transceive(
          Uint8List.fromList([0x00, 0xCA, 0x00, 0x00, 0x00]),
        );
        if (dataResp.length >= 4) {
          final payloadLen = (dataResp[0] << 8) | dataResp[1];
          if (dataResp.length >= 2 + payloadLen + 2) {
            return NfcLibTagResult(
              id: idHex,
              techList: techs,
              selectApduHex: selectHex,
              payload: utf8.decode(dataResp.sublist(2, 2 + payloadLen)),
            );
          }
        }
        return NfcLibTagResult(id: idHex, techList: techs, selectApduHex: selectHex,
            error: 'Respuesta incompleta: ${dataResp.length} bytes');
      }
      return NfcLibTagResult(id: idHex, techList: techs, selectApduHex: selectHex,
          error: 'AID no reconocido (no es app Monopoly)');
    } catch (e) {
      return NfcLibTagResult(id: idHex, techList: techs,
          error: e.toString().split('\n').first);
    }
  }

  Future<NfcLibTagResult> _readNdef(NfcTag tag) async {
    final tagAndroid = NfcTagAndroid.from(tag);
    String? idHex;
    String? techs;
    if (tagAndroid != null) {
      idHex = tagAndroid.id
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
      techs = tagAndroid.techList.join(', ');
    }

    final ndefAndroid = NdefAndroid.from(tag);
    if (ndefAndroid != null) {
      final msg = ndefAndroid.cachedNdefMessage;
      if (msg != null && msg.records.isNotEmpty) {
        try {
          final payload = msg.records.first.payload;
          final skip = payload.length > 3 ? 3 : 0;
          return NfcLibTagResult(
            id: idHex,
            techList: techs,
            ndefPayload: utf8.decode(payload.skip(skip).toList()),
          );
        } catch (_) {}
      }
    }

    return NfcLibTagResult(id: idHex, techList: techs, error: 'Sin datos NDEF');
  }
}
