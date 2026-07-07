import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class _AuditOperation {
  final String category;
  final String action;
  final DateTime startTime;
  DateTime? endTime;

  _AuditOperation({
    required this.category,
    required this.action,
    required this.startTime,
  });

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
}

class AppAuditLogger {
  AppAuditLogger._();

  static final AppAuditLogger instance = AppAuditLogger._();
  static const int _maxBytes = 1024 * 1024;
  Future<void> _writeChain = Future<void>.value();
  final Map<String, _AuditOperation> _pendingOps = {};

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(
        '${directory.path}${Platform.pathSeparator}monopoly_audit.log');
  }

  void _write(String entry) {
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
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
    });
  }

  /// Registra un evento puntual.
  void event(String module, String action,
      {Map<String, dynamic>? data, Object? error, StackTrace? stack}) {
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer('[$ts][$module] $action');
    if (data != null && data.isNotEmpty) {
      buf.write(' | ${jsonEncode(data)}');
    }
    if (error != null) buf.write('\n  ERROR: $error');
    if (stack != null) buf.write('\n  STACK: $stack');
    buf.write('\n');
    _write(buf.toString());
  }

  /// Inicia una operación con tracking de duración.
  /// Retorna un ID para llamar a [endOperation].
  String startOp(String module, String action,
      {Map<String, dynamic>? data}) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${action.hashCode}';
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer('[$ts][$module][START] $action');
    if (data != null && data.isNotEmpty) {
      buf.write(' | ${jsonEncode(data)}');
    }
    buf.write('\n');
    _write(buf.toString());
    _pendingOps[id] = _AuditOperation(
      category: module,
      action: action,
      startTime: DateTime.now(),
    );
    return id;
  }

  /// Finaliza una operación y registra su duración.
  void endOp(String id, {String? result, Object? error, StackTrace? stack}) {
    final op = _pendingOps.remove(id);
    final ts = DateTime.now().toIso8601String();
    final duration = op != null
        ? op.duration
        : const Duration(milliseconds: 0);
    final ms = duration.inMilliseconds;
    final buf = StringBuffer(
        '[$ts][${op?.category ?? '?'}][END  ] ${op?.action ?? '?'} (${ms}ms)');
    if (result != null) buf.write(' → $result');
    if (error != null) buf.write('\n  ERROR: $error');
    if (stack != null) buf.write('\n  STACK: $stack');
    buf.write('\n');
    _write(buf.toString());
  }

  /// Registra inicio + fin de una operación síncrona simple.
  void trace(String module, String action,
      {Map<String, dynamic>? data,
      String? result,
      Object? error,
      StackTrace? stack}) {
    final id = startOp(module, action, data: data);
    endOp(id, result: result, error: error, stack: stack);
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
