import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum AvatarMood { neutral, happy, sad, excited }

class AnimatedAvatar extends StatelessWidget {
  const AnimatedAvatar({
    super.key,
    required this.emoji,
    this.size = 64,
    this.glowColor,
    this.isSelected = false,
    this.showIdle = true,
    this.mood = AvatarMood.neutral,
    this.onTap,
  });

  final String emoji;
  final double size;
  final Color? glowColor;
  final bool isSelected;
  final bool showIdle;
  final AvatarMood mood;
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

    double idleFloat = 3;
    double idleDuration = 2000;
    double idleScaleBegin = 0.97;
    double idleScaleEnd = 1.0;
    int idleScaleDuration = 3000;

    switch (mood) {
      case AvatarMood.happy:
        idleFloat = 5;
        idleDuration = 1200;
        idleScaleBegin = 1.0;
        idleScaleEnd = 1.06;
        idleScaleDuration = 1500;
      case AvatarMood.excited:
        idleFloat = 7;
        idleDuration = 800;
        idleScaleBegin = 0.95;
        idleScaleEnd = 1.08;
        idleScaleDuration = 1000;
      case AvatarMood.sad:
        idleFloat = 1;
        idleDuration = 3000;
        idleScaleBegin = 0.98;
        idleScaleEnd = 0.95;
        idleScaleDuration = 4000;
      case AvatarMood.neutral:
        break;
    }

    return card
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .moveY(
            begin: -idleFloat,
            end: idleFloat,
            duration: idleDuration.ms,
            curve: Curves.easeInOut)
        .scale(
            begin: Offset(idleScaleBegin, idleScaleBegin),
            end: Offset(idleScaleEnd, idleScaleEnd),
            duration: idleScaleDuration.ms,
            curve: Curves.easeInOut);
  }
}
