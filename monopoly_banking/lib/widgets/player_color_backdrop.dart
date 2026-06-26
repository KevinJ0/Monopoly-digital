import 'dart:ui';

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
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      color.withValues(alpha: 0.176),
                      color.withValues(alpha: 0.096),
                      color.withValues(alpha: 0.032),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.27, 0.5, 0.72],
                  ),
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
