import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';

class MonopolyBackground extends StatefulWidget {
  final Widget child;

  const MonopolyBackground({super.key, required this.child});

  @override
  State<MonopolyBackground> createState() => _MonopolyBackgroundState();
}

class _MonopolyBackgroundState extends State<MonopolyBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _cycle = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _cycle++;
        _ctrl.forward(from: 0);
      }
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return RepaintBoundary(
          child: CustomPaint(
            painter: _MonopolyGridPainter(animationValue: _ctrl.value + _cycle),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _FloatingEmoji {
  final String emoji;
  final double size;
  final double opacity;
  final double speedX;
  final double speedY;
  final double rotationSpeed;
  final double startX;
  final double startY;

  const _FloatingEmoji({
    required this.emoji,
    required this.size,
    required this.opacity,
    required this.speedX,
    required this.speedY,
    required this.rotationSpeed,
    required this.startX,
    required this.startY,
  });
}

const _emojis = [
  _FloatingEmoji(emoji: '\u{1F4B0}', size: 30, opacity: 0.18, speedX: 0.12, speedY: 0.04, rotationSpeed: 0.3, startX: 0.0, startY: 0.0),
  _FloatingEmoji(emoji: '\u{1F4B5}', size: 26, opacity: 0.15, speedX: -0.08, speedY: 0.06, rotationSpeed: -0.4, startX: 0.3, startY: 0.1),
  _FloatingEmoji(emoji: '\u{1F4B2}', size: 28, opacity: 0.20, speedX: 0.15, speedY: -0.03, rotationSpeed: 0.25, startX: 0.6, startY: 0.2),
  _FloatingEmoji(emoji: '\u{1F3E0}', size: 32, opacity: 0.14, speedX: -0.06, speedY: 0.08, rotationSpeed: -0.2, startX: 0.1, startY: 0.4),
  _FloatingEmoji(emoji: '\u{1F3E8}', size: 36, opacity: 0.12, speedX: 0.10, speedY: -0.05, rotationSpeed: 0.15, startX: 0.5, startY: 0.6),
  _FloatingEmoji(emoji: '\u{1F682}', size: 28, opacity: 0.16, speedX: -0.12, speedY: 0.02, rotationSpeed: -0.35, startX: 0.8, startY: 0.3),
  _FloatingEmoji(emoji: '\u{1F3B2}', size: 24, opacity: 0.22, speedX: 0.07, speedY: -0.07, rotationSpeed: 0.5, startX: 0.2, startY: 0.7),
  _FloatingEmoji(emoji: '\u{2753}', size: 26, opacity: 0.15, speedX: -0.10, speedY: -0.04, rotationSpeed: -0.1, startX: 0.7, startY: 0.0),
  _FloatingEmoji(emoji: '\u{1F4E6}', size: 26, opacity: 0.13, speedX: 0.09, speedY: 0.05, rotationSpeed: 0.2, startX: 0.4, startY: 0.8),
  _FloatingEmoji(emoji: '\u{2B50}', size: 22, opacity: 0.25, speedX: -0.05, speedY: -0.06, rotationSpeed: -0.6, startX: 0.9, startY: 0.5),
  _FloatingEmoji(emoji: '\u{1F3A9}', size: 28, opacity: 0.12, speedX: 0.11, speedY: -0.02, rotationSpeed: 0.1, startX: 0.05, startY: 0.55),
  _FloatingEmoji(emoji: '\u{1F698}', size: 30, opacity: 0.14, speedX: -0.09, speedY: 0.07, rotationSpeed: -0.3, startX: 0.55, startY: 0.85),
  _FloatingEmoji(emoji: '\u{1F415}', size: 24, opacity: 0.11, speedX: 0.06, speedY: -0.08, rotationSpeed: 0.4, startX: 0.85, startY: 0.15),
  _FloatingEmoji(emoji: '\u{1F4B8}', size: 22, opacity: 0.20, speedX: -0.07, speedY: 0.09, rotationSpeed: -0.5, startX: 0.15, startY: 0.3),
  _FloatingEmoji(emoji: '\u{1F3B0}', size: 20, opacity: 0.18, speedX: 0.13, speedY: -0.04, rotationSpeed: 0.35, startX: 0.65, startY: 0.45),
  _FloatingEmoji(emoji: '\u{1F4B3}', size: 26, opacity: 0.16, speedX: -0.11, speedY: -0.05, rotationSpeed: -0.25, startX: 0.35, startY: 0.65),

  _FloatingEmoji(emoji: '\u{1F6F8}', size: 20, opacity: 0.12, speedX: 0.14, speedY: 0.03, rotationSpeed: 0.45, startX: 0.45, startY: 0.35),
  _FloatingEmoji(emoji: '\u{1F911}', size: 28, opacity: 0.17, speedX: -0.13, speedY: -0.03, rotationSpeed: -0.15, startX: 0.95, startY: 0.75),
  _FloatingEmoji(emoji: '\u{1F3AA}', size: 26, opacity: 0.10, speedX: 0.05, speedY: 0.10, rotationSpeed: 0.2, startX: 0.1, startY: 0.9),
  _FloatingEmoji(emoji: '\u{1F3AF}', size: 20, opacity: 0.19, speedX: -0.08, speedY: -0.07, rotationSpeed: -0.4, startX: 0.6, startY: 0.05),
  _FloatingEmoji(emoji: '\u{26F3}', size: 24, opacity: 0.11, speedX: 0.10, speedY: 0.04, rotationSpeed: 0.1, startX: 0.8, startY: 0.7),
  _FloatingEmoji(emoji: '\u{1F3C1}', size: 22, opacity: 0.16, speedX: -0.06, speedY: -0.10, rotationSpeed: -0.3, startX: 0.3, startY: 0.5),
];

class _MonopolyGridPainter extends CustomPainter {
  final double animationValue;
  _MonopolyGridPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = kBgDark;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    _drawGrid(canvas, size);
    _drawFloatingEmojis(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double gridOffset = animationValue * 120;
    const double gridSize = 80;

    for (double x = -gridSize + (gridOffset % gridSize);
        x < size.width;
        x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = -gridSize + (gridOffset % gridSize);
        y < size.height;
        y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawFloatingEmojis(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      fontSize: 20,
      color: Colors.white,
    );

    for (final e in _emojis) {
      final x = (_wrap(e.startX + animationValue * e.speedX) * size.width);
      final y = (_wrap(e.startY + animationValue * e.speedY) * size.height);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * e.rotationSpeed * math.pi * 2);

      final tp = TextPainter(
        text: TextSpan(
          text: e.emoji,
          style: textStyle.copyWith(
            fontSize: e.size,
            color: Colors.white.withValues(alpha: e.opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  double _wrap(double value) {
    final v = value % 1.4;
    if (v > 1.0) return v - 1.0;
    return v;
  }

  @override
  bool shouldRepaint(covariant _MonopolyGridPainter oldDelegate) {
    return (oldDelegate.animationValue - animationValue).abs() > 0.001;
  }
}
