import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'services/app_audit_logger.dart';
import 'services/error_translator_service.dart';
import 'services/foreground_service.dart';
import 'services/hive_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  if (sentryDsn.isEmpty) {
    await runAppWithSentry();
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;
      options.tracesSampleRate = 1.0;
      options.attachStacktrace = true;
      options.environment = kReleaseMode ? 'release' : 'debug';
    },
    appRunner: () => runAppWithSentry(),
  );
}

Future<void> runAppWithSentry() async {
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(420, 800),
      minimumSize: Size(420, 800),
      center: true,
      title: 'Money Manager',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

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
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
    FlutterError.dumpErrorToConsole(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppAuditLogger.instance.error(
      'UNCAUGHT_ERROR',
      error,
      stack: stack,
    );
    Sentry.captureException(error, stackTrace: stack);
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
    Sentry.captureException(e, stackTrace: stack);
    rethrow;
  }

  runApp(const MoneyManagerApp());
}
