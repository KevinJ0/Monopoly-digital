part of '../bank_screen.dart';

class _BankOperationDialogController {
  _BankOperationDialogController({required this.transportType})
      : title = ValueNotifier<String>('Preparando operación'),
        message = ValueNotifier<String>('Esperando conexión del jugador...'),
        debugInfo = ValueNotifier<String>('');

  final TransportType transportType;
  final ValueNotifier<String> title;
  final ValueNotifier<String> message;
  final ValueNotifier<String> debugInfo;
  final completed = ValueNotifier<bool>(false);
  final failed = ValueNotifier<bool>(false);
  final cancelled = ValueNotifier<bool>(false);
  IconData failedIcon = Icons.close_rounded;
  Color failedColor = kRed;

  void update({
    required String title,
    required String message,
  }) {
    if (completed.value || failed.value || cancelled.value) return;
    this.title.value = title;
    this.message.value = message;
  }

  void complete(String message) {
    completed.value = true;
    failed.value = false;
    title.value = 'Proceso completado';
    this.message.value = message;
  }

  void fail({
    required String title,
    required String message,
    IconData icon = Icons.close_rounded,
    Color color = kRed,
  }) {
    failedIcon = icon;
    failedColor = color;
    failed.value = true;
    completed.value = false;
    this.title.value = title;
    this.message.value = message;
  }
}
