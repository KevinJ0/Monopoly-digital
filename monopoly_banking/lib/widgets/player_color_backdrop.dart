import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';

class PlayerColorBackdrop extends StatelessWidget {
  final Color color;
  final Widget child;

  const PlayerColorBackdrop({
    super.key,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: kBgDark)),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomCenter,
                  radius: 1.2,
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.4, 0.7],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
