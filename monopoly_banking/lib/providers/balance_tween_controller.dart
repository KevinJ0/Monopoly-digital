import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

class BalanceTweenController {
  static final BalanceTweenController _instance = BalanceTweenController._();
  factory BalanceTweenController() => _instance;
  BalanceTweenController._();

  final ValueNotifier<double> displayBalance = ValueNotifier(0);

  AnimationController? _animController;
  Animation<double>? _tween;

  double _safeMoneyValue(double value) => value.isFinite ? value : 0;

  void attach(AnimationController controller) {
    _animController = controller;
  }

  void animateTo(double from, double to) {
    final safeFrom = _safeMoneyValue(from);
    final safeTo = _safeMoneyValue(to);
    final controller = _animController;
    if (controller == null) {
      displayBalance.value = safeTo;
      return;
    }

    controller.stop();
    _tween = Tween<double>(begin: safeFrom, end: safeTo).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        displayBalance.value = _safeMoneyValue(_tween!.value).roundToDouble();
      });

    controller.forward(from: 0);
  }

  void detach() {
    _animController?.dispose();
    _animController = null;
    _tween = null;
  }
}
