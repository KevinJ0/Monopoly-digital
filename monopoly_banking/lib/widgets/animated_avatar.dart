import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AnimatedAvatar extends StatelessWidget {
  const AnimatedAvatar({
    super.key,
    required this.emoji,
    this.size = 64,
    this.glowColor,
    this.isSelected = false,
    this.showIdle = true,
    this.onTap,
  });

  final String emoji;
  final double size;
  final Color? glowColor;
  final bool isSelected;
  final bool showIdle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveGlow = glowColor ?? Colors.green;
    final card = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: isSelected
              ? RadialGradient(
                  colors: [
                    effectiveGlow.withValues(alpha: 0.25),
                    effectiveGlow.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                )
              : null,
          color: isSelected
              ? effectiveGlow.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? effectiveGlow.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: effectiveGlow.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 3)
                ]
              : null,
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(fontSize: size * 0.45),
          ),
        ),
      ),
    );

    if (!showIdle) return card;

    return card
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .moveY(
            begin: -3,
            end: 3,
            duration: 2000.ms,
            curve: Curves.easeInOut)
        .scale(
            begin: const Offset(0.97, 0.97),
            end: const Offset(1.0, 1.0),
            duration: 3000.ms,
            curve: Curves.easeInOut);
  }
}
