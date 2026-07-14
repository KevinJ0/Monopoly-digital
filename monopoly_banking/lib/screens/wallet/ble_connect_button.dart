part of '../wallet_screen.dart';

class BleConnectButton extends StatefulWidget {
  final Color color;
  final bool bleScanning;
  final bool clientConnected;
  final bool connecting;
  final VoidCallback? onStartBleClient;
  final VoidCallback? onStopBleClient;

  const BleConnectButton({
    super.key,
    required this.color,
    this.bleScanning = false,
    this.clientConnected = false,
    this.connecting = false,
    this.onStartBleClient,
    this.onStopBleClient,
  });

  @override
  State<BleConnectButton> createState() => _BleConnectButtonState();
}

class _BleConnectButtonState extends State<BleConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  late final AnimationController _glideCtrl;

  late final AnimationController _heartbeatCtrl;
  late final Animation<double> _heartbeatAnim;
  late final Animation<double> _heartbeatGlow;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _glideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _heartbeatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _heartbeatAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.07), weight: 12),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.07, end: 0.95), weight: 10),
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.95, end: 1.0), weight: 28),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartbeatCtrl, curve: Curves.easeInOut));
    _heartbeatGlow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.8), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 0.8, end: 0.3), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: 0.3, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartbeatCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _glideCtrl.dispose();
    _heartbeatCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    SoundService.playClick();
    if (widget.clientConnected || widget.bleScanning || widget.connecting) {
      widget.onStopBleClient?.call();
    } else {
      widget.onStartBleClient?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final diameter = size.shortestSide * 0.45;
    final clampedDiameter = diameter.clamp(140.0, 220.0);
    final isActive =
        widget.bleScanning || widget.clientConnected || widget.connecting;
    final borderWidth = 2.5;

    return SafeArea(
      child: Center(
        child: GestureDetector(
          onTap: _onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: clampedDiameter + 40,
                height: clampedDiameter + 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.bleScanning)
                      AnimatedBuilder(
                        animation: _glideCtrl,
                        builder: (context, _) {
                          return CustomPaint(
                            size: Size(
                                clampedDiameter + 40, clampedDiameter + 40),
                            painter: _GlowRingPainter(
                              color: widget.color,
                              progress: _glideCtrl.value,
                              strokeWidth: borderWidth,
                            ),
                          );
                        },
                      ),
                    if (widget.connecting)
                      AnimatedBuilder(
                        animation: _heartbeatCtrl,
                        builder: (context, _) {
                          return CustomPaint(
                            size: Size(
                                clampedDiameter + 60, clampedDiameter + 60),
                            painter: _RipplePainter(
                              color: widget.color,
                              progress: _heartbeatAnim.value,
                              glow: _heartbeatGlow.value,
                            ),
                          );
                        },
                      ),
                    AnimatedBuilder(
                      animation: widget.connecting
                          ? _heartbeatCtrl
                          : _pulseCtrl,
                      builder: (context, _) {
                        final scale = widget.clientConnected
                            ? 1.0
                            : widget.connecting
                                ? _heartbeatAnim.value
                                : widget.bleScanning
                                    ? 1.0
                                    : (0.94 + 0.06 * _pulseAnim.value);
                        final glowAlpha = widget.clientConnected
                            ? 0.3
                            : widget.connecting
                                ? 0.15 + 0.5 * _heartbeatGlow.value
                                : widget.bleScanning
                                    ? (0.25 + 0.35 * _pulseAnim.value)
                                    : 0.15;
                        final borderGlow = widget.connecting
                            ? _heartbeatGlow.value
                            : 0.15;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: clampedDiameter,
                            height: clampedDiameter,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget.clientConnected
                                    ? [
                                        widget.color,
                                        widget.color.withValues(alpha: 0.55),
                                      ]
                                    : widget.connecting
                                        ? [
                                            widget.color,
                                            widget.color
                                                .withValues(alpha: 0.45),
                                          ]
                                        : widget.bleScanning
                                            ? [
                                                widget.color,
                                                widget.color
                                                    .withValues(alpha: 0.5),
                                              ]
                                            : [
                                                Colors.blue
                                                    .withValues(alpha: 0.35),
                                                Colors.blue
                                                    .withValues(alpha: 0.12),
                                              ],
                              ),
                              border: Border.all(
                                color: (isActive ? widget.color : Colors.white)
                                    .withValues(alpha: 0.1 + 0.35 * borderGlow),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isActive
                                          ? widget.color
                                          : Colors.blue)
                                      .withValues(alpha: glowAlpha),
                                  blurRadius: 30 + 25 * (widget.connecting
                                      ? _heartbeatGlow.value
                                      : _pulseAnim.value),
                                  spreadRadius: 4 + 8 * (widget.connecting
                                      ? _heartbeatGlow.value
                                      : _pulseAnim.value),
                                ),
                              ],
                            ),
                            child: Center(
                              child: widget.clientConnected
                                  ? Icon(
                                      Icons
                                          .bluetooth_connected_rounded,
                                      size: clampedDiameter * 0.4,
                                      color: Colors.white,
                                    )
                                  : widget.connecting
                                      ? AnimatedBuilder(
                                          animation: _heartbeatCtrl,
                                          builder: (context, _) {
                                            return Transform.rotate(
                                              angle: sin(_heartbeatCtrl
                                                      .value *
                                                  2 *
                                                  pi) *
                                                  0.08,
                                              child: Icon(
                                                Icons
                                                    .bluetooth_searching_rounded,
                                                size:
                                                    clampedDiameter * 0.38,
                                                color: Colors.white,
                                              ),
                                            );
                                          },
                                        )
                                      : widget.bleScanning
                                          ? AppSpinner(
                                              size: clampedDiameter * 0.35,
                                              color: widget.color,
                                            )
                                          : Icon(
                                              Icons
                                                  .bluetooth_searching_rounded,
                                              size: clampedDiameter * 0.38,
                                              color: Colors.white
                                                  .withValues(alpha: 0.8),
                                            ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.clientConnected
                    ? 'CONECTADO'
                    : widget.connecting
                        ? 'CONECTANDO...'
                        : widget.bleScanning
                            ? 'BUSCANDO BANCOS...'
                            : 'CONECTAR POR BLE',
                style: TextStyle(
                  color: widget.clientConnected
                      ? widget.color
                      : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.connecting
                    ? 'Estableciendo conexión con el banco'
                    : widget.bleScanning
                        ? 'Mantén el dispositivo cerca del banco'
                        : widget.clientConnected
                            ? 'Toca para desconectar'
                            : 'Toca para buscar bancos cercanos',
                style: const TextStyle(
                  color: kTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  final Color color;
  final double progress;
  final double strokeWidth;

  _GlowRingPainter({
    required this.color,
    required this.progress,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    paint.color = color.withValues(alpha: 0.1);
    canvas.drawCircle(center, radius, paint);

    paint.color = color;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    glowPaint.color = color.withValues(alpha: 0.2);

    final sweepAngle = pi * 0.35;
    final startAngle = -pi / 2 + progress * 2 * pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false, glowPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false, paint,
    );
  }

  @override
  bool shouldRepaint(_GlowRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _RipplePainter extends CustomPainter {
  final Color color;
  final double progress;
  final double glow;

  _RipplePainter({
    required this.color,
    required this.progress,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final ringProgress = (progress - 0.85).clamp(0.0, 1.0);
    if (ringProgress <= 0) return;

    final radius = maxRadius * 0.5 + maxRadius * 0.5 * ringProgress;
    final alpha = (1 - ringProgress) * glow;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * (1 - ringProgress) + 0.5
      ..color = color.withValues(alpha: 0.4 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.glow != glow;
}
