part of '../wallet_screen.dart';

class BleConnectButton extends StatefulWidget {
  final Color color;
  final bool bleScanning;
  final bool clientConnected;
  final VoidCallback? onStartBleClient;
  final VoidCallback? onStopBleClient;

  const BleConnectButton({
    super.key,
    required this.color,
    this.bleScanning = false,
    this.clientConnected = false,
    this.onStartBleClient,
    this.onStopBleClient,
  });

  @override
  State<BleConnectButton> createState() => _BleConnectButtonState();
}

class _BleConnectButtonState extends State<BleConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

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
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    SoundService.playClick();
    if (widget.clientConnected || widget.bleScanning) {
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
    final isActive = widget.bleScanning || widget.clientConnected;

    return SafeArea(
      child: Center(
        child: GestureDetector(
          onTap: _onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: clampedDiameter + 80,
                height: clampedDiameter + 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.bleScanning)
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (context, _) {
                          return Container(
                            width: clampedDiameter + 20,
                            height: clampedDiameter + 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.color
                                    .withValues(alpha: 0.3 * _pulseAnim.value),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, _) {
                        final scale = widget.bleScanning
                            ? 1.0
                            : (0.95 + 0.05 * _pulseAnim.value);
                        final shadowAlpha =
                            isActive ? (0.2 + 0.3 * _pulseAnim.value) : 0.2;
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
                                colors: isActive
                                    ? [
                                        widget.color,
                                        widget.color.withValues(alpha: 0.6),
                                      ]
                                    : [
                                        Colors.blue.withValues(alpha: 0.3),
                                        Colors.blue.withValues(alpha: 0.1),
                                      ],
                              ),
                              border: Border.all(
                                color: (isActive ? widget.color : Colors.white)
                                    .withValues(
                                        alpha: widget.bleScanning
                                            ? 0.15 + 0.2 * _pulseAnim.value
                                            : 0.15),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isActive ? widget.color : Colors.blue)
                                      .withValues(alpha: shadowAlpha),
                                  blurRadius: 30 + 20 * _pulseAnim.value,
                                  spreadRadius: 4 + 6 * _pulseAnim.value,
                                ),
                              ],
                            ),
                            child: Center(
                              child: widget.bleScanning
                                  ? AppSpinner(
                                      size: clampedDiameter * 0.35,
                                      color: widget.color,
                                    )
                                  : Icon(
                                      Icons.bluetooth_rounded,
                                      size: clampedDiameter * 0.38,
                                      color: Colors.white,
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
                    : widget.bleScanning
                        ? 'BUSCANDO BANCOS...'
                        : 'CONECTAR POR BLE',
                style: TextStyle(
                  color: widget.clientConnected ? widget.color : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.bleScanning
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
