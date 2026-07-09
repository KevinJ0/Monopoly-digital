import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:monopoly_banking/app.dart';
import 'package:monopoly_banking/services/app_audit_logger.dart';
import 'package:monopoly_banking/services/ble_diagnostic_logger.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capturar errores de Flutter (errores en widgets, render, etc.)
  FlutterError.onError = (details) {
    AppAuditLogger.instance.error(
      'FLUTTER_ERROR',
      details.exception,
      stack: details.stack,
      data: {
        'library': details.library,
        'context': details.context?.toString(),
        'silent': details.silent,
      },
    );
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  // Capturar errores asíncronos no atrapados y errores de plataforma
  PlatformDispatcher.instance.onError = (error, stack) {
    AppAuditLogger.instance.error(
      'UNCAUGHT_ERROR',
      error,
      stack: stack,
    );
    return true;
  };

  if (kDebugMode) {
    await BleDiagnosticLogger.instance.clear();
    BleDiagnosticLogger.instance.logEvent('APP', 'start');
  }

  try {
    await HiveService.init();
    await SoundService.init();
    await ErrorTranslatorService().init();
    AppAuditLogger.instance.event('APP', 'initialized');
  } catch (e, stack) {
    AppAuditLogger.instance.error('APP_INIT', e, stack: stack);
    rethrow;
  }

  runApp(const MonopolyApp());
}
