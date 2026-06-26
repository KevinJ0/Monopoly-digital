import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

class BalanceTweenController {
  static final BalanceTweenController _instance = BalanceTweenController._();
  factory BalanceTweenController() => _instance;
  BalanceTweenController._();

  final ValueNotifier<double> displayBalance = ValueNotifier(0);

  AnimationController? _animController;
  Animation<double>? _tween;

  void attach(AnimationController controller) {
    _animController = controller;
  }

  void animateTo(double from, double to) {
    final controller = _animController;
    if (controller == null) {
      displayBalance.value = to;
      return;
    }

    controller.stop();
    _tween = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        displayBalance.value = _tween!.value.roundToDouble();
      });

    controller.forward(from: 0);
  }

  void detach() {
    _animController?.dispose();
    _animController = null;
    _tween = null;
  }
}
