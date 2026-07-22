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

class GameDialogRoute<T> extends PageRouteBuilder<T> {
  GameDialogRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool barrierDismissible = true,
    Color? barrierColor,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
              reverseCurve: Curves.easeInCubic,
            );
            return ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1.0).animate(curved),
              child: FadeTransition(
                opacity:
                    Tween<double>(begin: 0.0, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          opaque: false,
          barrierDismissible: barrierDismissible,
          barrierColor: barrierColor ?? Colors.black54,
          barrierLabel: 'Cerrar diálogo',
          settings: settings,
        );
}

Future<T?> showGameDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    GameDialogRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
    ),
  );
}
