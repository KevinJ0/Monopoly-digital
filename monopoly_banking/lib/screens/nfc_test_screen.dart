import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/nfc_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

class NfcTestScreen extends StatefulWidget {
  const NfcTestScreen({super.key});

  @override
  State<NfcTestScreen> createState() => _NfcTestScreenState();
}

class _NfcTestScreenState extends State<NfcTestScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.monopoly/nfc');

  NfcAvailability _availability = NfcAvailability.unsupported;
  bool _scanning = false;
  bool _hceActive = false;
  bool _processing = false; // evita llamadas concurrentes de onDiscovered
  final List<_LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNfc();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_scanning) {
      NfcManager.instance.stopSession().catchError((_) {});
    }
    if (_hceActive) {
      NfcService().stopHce().catchError((_) {});
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNfc();
    }
  }

  Future<void> _checkNfc() async {
    final avail = await NfcService().checkAvailability();
    if (!mounted) return;
    setState(() => _availability = avail);
    _addLog(
      _availabilityLabel(avail),
      avail == NfcAvailability.enabled ? _LogLevel.ok : _LogLevel.warn,
    );
  }

  void _addLog(String msg, _LogLevel level) {
    final now = TimeOfDay.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, _LogEntry(ts: ts, msg: msg, level: level));
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  String _availabilityLabel(NfcAvailability a) {
    switch (a) {
      case NfcAvailability.enabled:
        return 'NFC: ACTIVO y listo';
      case NfcAvailability.disabled:
        return 'NFC: DESACTIVADO (hardware presente)';
      case NfcAvailability.unsupported:
        return 'NFC: NO SOPORTADO en este dispositivo';
    }
  }

  Future<void> _startScan() async {
    if (_scanning) {
      _addLog('Ya hay un escaneo activo', _LogLevel.warn);
      return;
    }
    if (_availability != NfcAvailability.enabled) {
      _addLog('NFC no está activo — actívalo primero', _LogLevel.error);
      return;
    }
    setState(() => _scanning = true);
    _addLog('Escaneando... acerca cualquier dispositivo NFC', _LogLevel.info);

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          if (_processing) return;
          _processing = true;
          try {
            _onTagDiscovered(tag);
          } finally {
            // Pausa corta antes de aceptar el siguiente tag
            // evita acumulación de handles muertos
            await Future.delayed(const Duration(milliseconds: 800));
            _processing = false;
          }
        },
      );
    } catch (e, s) {
      _addLog('Error al iniciar sesión NFC: $e', _LogLevel.error);
      if (mounted) context.showFriendlyError(e, s);
      setState(() => _scanning = false);
    }
  }

  Future<void> _stopScan() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    setState(() {
      _scanning = false;
      _processing = false;
    });
    _addLog('Escaneo detenido manualmente', _LogLevel.info);
  }

  /// Reinicia la sesión NFC silenciosamente (tras un error de handle muerto)
  Future<void> _restartScan() async {
    setState(() {
      _scanning = true;
      _processing = false;
    });
    _addLog('Reiniciando sesión NFC...', _LogLevel.info);
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          if (_processing) return;
          _processing = true;
          try {
            _onTagDiscovered(tag);
          } finally {
            await Future.delayed(const Duration(milliseconds: 800));
            _processing = false;
          }
        },
      );
    } catch (e, s) {
      _addLog('Error al reiniciar sesión: $e', _LogLevel.error);
      if (mounted) context.showFriendlyError(e, s);
      setState(() => _scanning = false);
    }
  }

  // ── HCE ────────────────────────────────────────────────────────
  Future<void> _startHce() async {
    if (_availability != NfcAvailability.enabled) {
      _addLog('NFC no está activo', _LogLevel.error);
      return;
    }
    final testPayload = {
      'type': 'hce_test',
      'message': 'Hola desde HCE',
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await NfcService().startHce(testPayload);
      setState(() => _hceActive = true);
      _addLog(
          'HCE ACTIVO — este dispositivo emula una tarjeta NFC', _LogLevel.ok);
      _addLog('Acerca el otro dispositivo en modo escaneo', _LogLevel.info);
    } catch (e, s) {
      _addLog('Error al activar HCE: $e', _LogLevel.error);
      if (mounted) context.showFriendlyError(e, s);
    }
  }

  Future<void> _stopHce() async {
    try {
      await NfcService().stopHce();
    } catch (_) {}
    setState(() => _hceActive = false);
    _addLog('HCE desactivado', _LogLevel.info);
  }

  void _onTagDiscovered(NfcTag tag) async {
    // ── APDU primero, sin setState entre medio ──────────────────────
    final isoDep = IsoDepAndroid.from(tag);
    if (isoDep != null) {
      // Recoger info del tag para loggear DESPUÉS del exchange
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

      String? selectHex;
      String? payloadResult;
      String? errorMsg;

      try {
        // 1. SELECT AID — sin await extras previos
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
        selectHex = selectResp
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .toUpperCase();

        final apduOk = selectResp.length >= 2 &&
            selectResp[selectResp.length - 2] == 0x90 &&
            selectResp[selectResp.length - 1] == 0x00;

        if (apduOk) {
          // 2. GET DATA
          final dataResp = await isoDep.transceive(
            Uint8List.fromList([0x00, 0xCA, 0x00, 0x00, 0x00]),
          );
          if (dataResp.length >= 4) {
            final payloadLen = (dataResp[0] << 8) | dataResp[1];
            if (dataResp.length >= 2 + payloadLen + 2) {
              payloadResult = utf8.decode(dataResp.sublist(2, 2 + payloadLen));
            } else {
              payloadResult =
                  '[respuesta incompleta: ${dataResp.length} bytes]';
            }
          } else {
            payloadResult = '[sin datos en HCE]';
          }
        }
      } catch (e) {
        // Solo la primera línea del error — la pila completa no aporta
        errorMsg = e.toString().split('\n').first;
      }

      // Ahora sí loggeamos todo de golpe
      _addLog('━━━ DISPOSITIVO DETECTADO (IsoDep/HCE) ━━━', _LogLevel.ok);
      if (idHex != null) _addLog('ID: $idHex', _LogLevel.ok);
      if (techs != null) _addLog('Techs: $techs', _LogLevel.info);
      if (selectHex != null) _addLog('SELECT AID → $selectHex', _LogLevel.info);
      if (errorMsg != null) {
        _addLog('Error APDU: $errorMsg', _LogLevel.error);
        _addLog('→ Mantén los teléfonos quietos y pegados', _LogLevel.warn);
        // Reiniciar sesión para limpiar handles muertos
        if (_scanning) {
          await NfcManager.instance.stopSession().catchError((_) {});
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && _scanning) _restartScan();
        }
      } else if (payloadResult != null) {
        _addLog('AID reconocido ✓', _LogLevel.ok);
        _addLog('Payload: $payloadResult', _LogLevel.ok);
      } else if (selectHex != null) {
        _addLog('AID no reconocido (no es app Monopoly)', _LogLevel.warn);
      }
      _addLog('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', _LogLevel.ok);
      return;
    }

    // ── Fallback: NDEF pasivo ─────────────────────────────────────
    final tagAndroid = NfcTagAndroid.from(tag);
    _addLog('━━━ TAG PASIVO DETECTADO ━━━', _LogLevel.ok);
    if (tagAndroid != null) {
      final idHex = tagAndroid.id
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
      _addLog('ID: $idHex', _LogLevel.ok);
      _addLog('Techs: ${tagAndroid.techList.join(', ')}', _LogLevel.info);
    }
    final ndefAndroid = NdefAndroid.from(tag);
    if (ndefAndroid != null) {
      _addLog('NDEF Android detectado', _LogLevel.info);
      _addLog('  ¿Escribible?: ${ndefAndroid.isWritable}', _LogLevel.info);
      _addLog('  Max size: ${ndefAndroid.maxSize} bytes', _LogLevel.info);
      final msg = ndefAndroid.cachedNdefMessage;
      if (msg != null && msg.records.isNotEmpty) {
        _addLog('  Registros NDEF: ${msg.records.length}', _LogLevel.info);
        for (int i = 0; i < msg.records.length; i++) {
          final rec = msg.records[i];
          try {
            final payload = rec.payload;
            final skip = payload.length > 3 ? 3 : 0;
            final json = utf8.decode(payload.skip(skip).toList());
            _addLog('  Registro[$i] (JSON): $json', _LogLevel.ok);
          } catch (_) {
            _addLog(
                '  Registro[$i] (raw bytes): ${rec.payload}', _LogLevel.info);
          }
        }
      } else {
        _addLog('  Sin mensaje NDEF almacenado', _LogLevel.warn);
      }
    }

    _addLog('━━━━━━━━━━━━━━━━━━━━━━━━━━━━', _LogLevel.ok);
  }

  Future<void> _openNfcSettings() async {
    try {
      await _channel.invokeMethod<void>('openNfcSettings');
      _addLog('Abriendo ajustes de NFC del sistema...', _LogLevel.info);
    } catch (e, s) {
      _addLog('No se pudo abrir ajustes: $e', _LogLevel.error);
      if (mounted) context.showFriendlyError(e, s);
    }
  }

  Color _levelColor(_LogLevel level) {
    switch (level) {
      case _LogLevel.ok:
        return kGreen;
      case _LogLevel.info:
        return kTextSecondary;
      case _LogLevel.warn:
        return kGold;
      case _LogLevel.error:
        return kRed;
    }
  }

  IconData _levelIcon(_LogLevel level) {
    switch (level) {
      case _LogLevel.ok:
        return Icons.check_circle_outline_rounded;
      case _LogLevel.info:
        return Icons.info_outline_rounded;
      case _LogLevel.warn:
        return Icons.warning_amber_rounded;
      case _LogLevel.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = _availability == NfcAvailability.enabled;
    final isUnsupported = _availability == NfcAvailability.unsupported;

    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kTextSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'NFC Debug',
          style: TextStyle(
              color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
            tooltip: 'Re-verificar estado NFC',
            onPressed: _checkNfc,
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: kTextSecondary),
            tooltip: 'Copiar todos los logs',
            onPressed: () {
              if (_logs.isEmpty) return;
              final text =
                  _logs.reversed.map((e) => '[${e.ts}] ${e.msg}').join('\n');
              Clipboard.setData(ClipboardData(text: text));
              NotificationService().show('Logs copiados al portapapeles',
                  duration: const Duration(seconds: 2));
            },
          ),
          IconButton(
            icon:
                const Icon(Icons.delete_outline_rounded, color: kTextSecondary),
            tooltip: 'Limpiar logs',
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Estado NFC ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isEnabled
                    ? kGreen.withValues(alpha: 0.4)
                    : isUnsupported
                        ? kRed.withValues(alpha: 0.4)
                        : kGold.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.nfc_rounded,
                      color: isEnabled
                          ? kGreen
                          : isUnsupported
                              ? kRed
                              : kGold,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estado del NFC',
                            style: TextStyle(
                              color: kTextSecondary,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEnabled
                                ? 'ACTIVO'
                                : isUnsupported
                                    ? 'NO SOPORTADO'
                                    : 'DESACTIVADO',
                            style: TextStyle(
                              color: isEnabled
                                  ? kGreen
                                  : isUnsupported
                                      ? kRed
                                      : kGold,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled
                            ? kGreen
                            : isUnsupported
                                ? kRed
                                : kGold,
                        boxShadow: [
                          BoxShadow(
                            color: (isEnabled
                                    ? kGreen
                                    : isUnsupported
                                        ? kRed
                                        : kGold)
                                .withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isEnabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isUnsupported ? null : _openNfcSettings,
                      icon: const Icon(Icons.settings_rounded, size: 16),
                      label: Text(isUnsupported
                          ? 'Hardware no disponible'
                          : 'Abrir ajustes para activar NFC'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGold,
                        side: BorderSide(color: kGold.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Acciones ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _scanning ? null : (isEnabled ? _startScan : null),
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label:
                        Text(_scanning ? 'Escaneando...' : 'Iniciar escaneo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isEnabled ? kGreen : Colors.grey.shade800,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? _stopScan : null,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Detener'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _scanning ? kRed : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── HCE: Simular tarjeta ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _hceActive ? null : (isEnabled ? _startHce : null),
                    icon: _hceActive
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.contactless_rounded, size: 18),
                    label:
                        Text(_hceActive ? 'Emitiendo...' : 'Simular tarjeta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hceActive
                          ? Colors.blue.shade800
                          : (isEnabled
                              ? Colors.blue.shade600
                              : Colors.grey.shade800),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _hceActive ? _stopHce : null,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Parar tarjeta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hceActive
                          ? Colors.orange.shade700
                          : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded,
                    color: kTextSecondary, size: 14),
                const SizedBox(width: 6),
                const Text(
                  'LOG EN TIEMPO REAL',
                  style: TextStyle(
                      color: kTextSecondary,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${_logs.length} entradas',
                  style: const TextStyle(color: kTextSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Lista de logs ────────────────────────────────────────────
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF060B14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nfc_rounded,
                              color: Colors.white12, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Pulsa "Iniciar escaneo" y\nacerca un dispositivo NFC',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white24, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      reverse: false,
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final e = _logs[i];
                        return GestureDetector(
                          onLongPress: () {
                            Clipboard.setData(
                                ClipboardData(text: '[${e.ts}] ${e.msg}'));
                            NotificationService().show('Línea copiada',
                                duration: const Duration(seconds: 1));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.ts,
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(_levelIcon(e.level),
                                    color: _levelColor(e.level), size: 13),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    e.msg,
                                    style: TextStyle(
                                      color: _levelColor(e.level),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LogEntry {
  final String ts;
  final String msg;
  final _LogLevel level;
  _LogEntry({required this.ts, required this.msg, required this.level});
}

enum _LogLevel { ok, info, warn, error }
