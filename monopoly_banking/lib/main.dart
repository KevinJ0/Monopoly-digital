import 'package:flutter/material.dart';
import 'package:monopoly_banking/app.dart';
import 'package:monopoly_banking/services/hive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  runApp(const MonopolyApp());
}
