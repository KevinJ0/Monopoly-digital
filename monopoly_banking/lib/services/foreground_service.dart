import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';

class BankForegroundService {
  static final BankForegroundService _instance = BankForegroundService._();
  factory BankForegroundService() => _instance;
  BankForegroundService._();

  static const _notificationId = 8881;

  Future<void> init() async {
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
        initialNotificationTitle: 'Banca Central',
        initialNotificationContent: 'Servidor activo',
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
        onStart: onStart,
      ),
    );
  }

  Future<void> start() async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    }
  }

  Future<void> stop() async {
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
