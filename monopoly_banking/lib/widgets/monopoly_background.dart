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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
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
        return CustomPaint(
          painter: _MonopolyGridPainter(animationValue: _ctrl.value),
          child: widget.child,
        );
      },
    );
  }
}

class _MonopolyGridPainter extends CustomPainter {
  final double animationValue;

  _MonopolyGridPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = kBgDark;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final double gridOffset = animationValue * 150;
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

    final moneyPaint = Paint()
      ..color = kGold.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      final double x = (size.width * 0.2 * i +
              (animationValue * size.width * (i.isEven ? 0.3 : -0.2))) %
          size.width;
      final double y = (size.height * 0.3 * i +
              (animationValue * size.height * (i.isEven ? -0.2 : 0.4))) %
          size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * 2 * math.pi * (i.isEven ? 1 : -1));
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 40, height: 60),
          moneyPaint);
      canvas.restore();
    }

    final housePaint = Paint()
      ..color = kGreenGlow.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final double x = (size.width * 0.25 * i +
              (animationValue * size.width * (i.isEven ? -0.4 : 0.3))) %
          size.width;
      final double y = (size.height * 0.25 * i +
              (animationValue * size.height * (i.isEven ? 0.3 : -0.3))) %
          size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * 2 * math.pi * (i.isEven ? -1 : 1));

      final path = Path()
        ..moveTo(-15, 0)
        ..lineTo(0, -15)
        ..lineTo(15, 0)
        ..lineTo(15, 15)
        ..lineTo(-15, 15)
        ..close();

      canvas.drawPath(path, housePaint);
      canvas.restore();
    }

    final dicePaint = Paint()
      ..color = kGold.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      final double x = (size.width * 0.3 * i +
              (animationValue * size.width * (i.isEven ? -0.25 : 0.35))) %
          size.width;
      final double y = (size.height * 0.4 * i +
              (animationValue * size.height * (i.isEven ? 0.25 : -0.35))) %
          size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * 3 * math.pi * (i.isEven ? 1 : -1));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 18, height: 18),
              const Radius.circular(4)),
          dicePaint);
      canvas.restore();
    }

    final trainPaint = Paint()
      ..color = kRed.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < 3; i++) {
      final double x = (size.width * 0.35 + animationValue * size.width * 0.3) %
          size.width;
      final double y =
          (size.height * 0.2 + i * size.height * 0.3) % size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.drawCircle(Offset.zero, 22, trainPaint);
      canvas.drawCircle(const Offset(16, 0), 16, trainPaint);
      canvas.drawCircle(const Offset(-16, 0), 16, trainPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MonopolyGridPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
