import 'package:flutter/material.dart';
import 'package:monopoly_banking/app.dart';
import 'package:monopoly_banking/services/ble_diagnostic_logger.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BleDiagnosticLogger.instance.clear();
  BleDiagnosticLogger.instance.logEvent('APP', 'start');
  await HiveService.init();
  await SoundService.init();
  await ErrorTranslatorService().init();
  runApp(const MonopolyApp());
}
