import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'services/app_audit_logger.dart';
import 'services/error_translator_service.dart';
import 'services/foreground_service.dart';
import 'services/hive_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  PlatformDispatcher.instance.onError = (error, stack) {
    AppAuditLogger.instance.error(
      'UNCAUGHT_ERROR',
      error,
      stack: stack,
    );
    return true;
  };

  try {
    await HiveService.init();
    await SoundService.init();
    await ErrorTranslatorService().init();
    await BankForegroundService().init();
    AppAuditLogger.instance.event('APP', 'initialized');
  } catch (e, stack) {
    AppAuditLogger.instance.error('APP_INIT', e, stack: stack);
    rethrow;
  }

  runApp(const MonopolyApp());
}
