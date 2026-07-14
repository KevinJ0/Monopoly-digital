part of '../bank_screen.dart';

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.progress,
    required this.delay,
    required this.color,
  });

  final double progress;
  final double delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final adjusted = (progress + delay) % 1;
    final size = 72 + (adjusted * 58);
    final opacity = (1 - adjusted).clamp(0.0, 1.0) * 0.32;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}
