import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final Color? _barrierColor;

  @override
  Color? get barrierColor => _barrierColor;

  GameFadeRoute({required this.page, Color? barrierColor})
      : _barrierColor = barrierColor,
        super(
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
    super.settings,
    super.barrierDismissible = true,
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
          barrierColor: barrierColor ?? Colors.black54,
          barrierLabel: 'Cerrar diálogo',
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
      builder: (ctx) => _EnterKeyHandler(child: builder(ctx)),
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
    ),
  );
}

class _EnterKeyHandler extends StatefulWidget {
  final Widget child;
  const _EnterKeyHandler({required this.child});

  @override
  State<_EnterKeyHandler> createState() => _EnterKeyHandlerState();
}

class _EnterKeyHandlerState extends State<_EnterKeyHandler> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return;
    }

    // Walk child tree to find the first ElevatedButton (primary action)
    ElevatedButton? primary;
    void visit(Element el) {
      if (primary != null) return;
      if (el.widget is ElevatedButton) {
        primary = el.widget as ElevatedButton;
        return;
      }
      el.visitChildren(visit);
    }
    context.visitChildElements(visit);
    if (primary != null && primary!.onPressed != null) {
      primary!.onPressed!.call();
      return;
    }

    // Fallback: find first TextButton with a callback
    TextButton? fallback;
    void visitFallback(Element el) {
      if (fallback != null) return;
      if (el.widget is TextButton) {
        final btn = el.widget as TextButton;
        if (btn.onPressed != null) fallback = btn;
        return;
      }
      el.visitChildren(visitFallback);
    }
    context.visitChildElements(visitFallback);
    fallback?.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter;
        if ((event is KeyDownEvent || event is KeyRepeatEvent) && isEnter) {
          _handleKey(event);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
