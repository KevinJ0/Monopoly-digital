import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BleDiagnosticLogger {
  BleDiagnosticLogger._();

  static final BleDiagnosticLogger instance = BleDiagnosticLogger._();
  static const int _maxBytes = 1024 * 1024;
  Future<void> _writeChain = Future<void>.value();

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(
        '${directory.path}${Platform.pathSeparator}ble_diagnostics.log');
  }

  void log(String source, String message, {Object? error, StackTrace? stack}) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = StringBuffer('[$timestamp][$source] $message');
    if (error != null) entry.write('\nERROR: $error');
    if (stack != null) entry.write('\nSTACK: $stack');
    entry.write('\n');

    _writeChain = _writeChain.catchError((_) {}).then((_) async {
      final file = await _file();
      if (await file.exists() && await file.length() >= _maxBytes) {
        final content = await file.readAsString();
        final keepFrom = content.length ~/ 2;
        final lineStart = content.indexOf('\n', keepFrom);
        await file.writeAsString(
          lineStart >= 0 ? content.substring(lineStart + 1) : '',
          flush: true,
        );
      }
      await file.writeAsString(
        entry.toString(),
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  /// Registra un evento estructurado (UI/BLE/etc) para auditoría de flujo.
  void logEvent(String category, String action, {Map<String, dynamic>? params}) {
    final buffer = StringBuffer('$category | $action');
    if (params != null && params.isNotEmpty) {
      buffer.write(' | ${jsonEncode(params)}');
    }
    log('EVENT', buffer.toString());
  }

  /// Registra un error con contexto.
  void logError(String context, Object error, {StackTrace? stack}) {
    log('ERROR', context, error: error, stack: stack);
  }

  Future<String> read() async {
    await _writeChain.catchError((_) {});
    final file = await _file();
    return await file.exists() ? file.readAsString() : '';
  }

  Future<String> get path async => (await _file()).path;

  Future<void> clear() async {
    await _writeChain.catchError((_) {});
    final file = await _file();
    if (await file.exists()) await file.writeAsString('', flush: true);
  }
}
