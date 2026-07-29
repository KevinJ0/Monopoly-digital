import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class BankForegroundService {
  static final BankForegroundService _instance = BankForegroundService._();
  factory BankForegroundService() => _instance;
  BankForegroundService._();

  static const _notificationId = 8881;

  Future<void> init() async {
    if (!kIsWeb && Platform.isWindows) return;

    final service = FlutterBackgroundService();

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: (instance) => true,
      ),
      androidConfiguration: AndroidConfiguration(
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: _notificationId,
        initialNotificationTitle: 'Banco Monopoly',
        initialNotificationContent: 'Servidor activo',
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
        onStart: onStart,
      ),
    );
  }

  Future<void> start() async {
    if (!kIsWeb && Platform.isWindows) return;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    }
  }

  Future<void> stop() async {
    if (!kIsWeb && Platform.isWindows) return;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (running) {
      service.invoke('stop');
    }
  }

  static void onStart(ServiceInstance service) {
    service.on('stop').listen((_) {
      service.stopSelf();
    });
  }
}
