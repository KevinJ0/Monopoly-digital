import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final List<_Notification> _queue = [];
  static const int _maxQueue = 3;
  bool _isShowing = false;

  void show(
    String message, {
    Color? backgroundColor,
    Duration? duration,
  }) {
    _queue.add(_Notification(message, backgroundColor, duration));
    while (_queue.length > _maxQueue) {
      _queue.removeAt(0);
    }
    _processQueue();
  }

  void _processQueue() {
    if (_queue.isEmpty || _isShowing) return;
    _isShowing = true;
    final notif = _queue.removeAt(0);

    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) {
      _isShowing = false;
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(notif.message,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: notif.backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: notif.duration ?? const Duration(seconds: 3),
      ),
    );

    Future.delayed(notif.duration ?? const Duration(seconds: 3), () {
      _isShowing = false;
      _processQueue();
    });
  }
}

class _Notification {
  final String message;
  final Color? backgroundColor;
  final Duration? duration;
  const _Notification(this.message, this.backgroundColor, this.duration);
}
