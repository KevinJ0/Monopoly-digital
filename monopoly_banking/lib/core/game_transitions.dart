import 'package:flutter/material.dart';

class GameSlideRoute extends PageRouteBuilder {
  final Widget page;
  final Offset begin;

  GameSlideRoute({
    required this.page,
    this.begin = const Offset(0.0, 0.08),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const curve = Curves.easeOutBack;
            final curved = CurvedAnimation(parent: animation, curve: curve);
            return SlideTransition(
              position: Tween<Offset>(begin: begin, end: Offset.zero)
                  .animate(curved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        );
}

class GameScaleRoute extends PageRouteBuilder {
  final Widget page;

  GameScaleRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const curve = Curves.easeOutBack;
            final curved = CurvedAnimation(parent: animation, curve: curve);
            return ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 600),
        );
}

class GameFadeRoute extends PageRouteBuilder {
  final Widget page;
  final Color? barrierColor;

  GameFadeRoute({required this.page, this.barrierColor})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            );
            return FadeTransition(opacity: curved, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
          opaque: barrierColor == null,
        );
}
