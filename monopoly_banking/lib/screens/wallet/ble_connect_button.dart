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
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
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

    return SafeArea(
      child: Center(
        child: GestureDetector(
          onTap: _onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _scaleCtrl,
                builder: (context, _) {
                  final scale = widget.clientConnected
                      ? 1.0
                      : widget.connecting
                          ? 1.0
                          : widget.bleScanning
                              ? _scaleAnim.value
                              : 1.0;
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
                                      widget.color.withValues(alpha: 0.45),
                                    ]
                                  : widget.bleScanning
                                      ? [
                                          widget.color,
                                          widget.color.withValues(alpha: 0.5),
                                        ]
                                      : [
                                          Colors.blue.withValues(alpha: 0.35),
                                          Colors.blue.withValues(alpha: 0.12),
                                        ],
                        ),
                        border: Border.all(
                          color: (isActive ? widget.color : Colors.white)
                              .withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: widget.clientConnected
                            ? Icon(
                                Icons.bluetooth_connected_rounded,
                                size: clampedDiameter * 0.4,
                                color: Colors.white,
                              )
                            : widget.connecting
                                ? Icon(
                                    Icons.bluetooth_searching_rounded,
                                    size: clampedDiameter * 0.38,
                                    color: Colors.white,
                                  )
                                : widget.bleScanning
                                    ? AppSpinner(
                                        size: clampedDiameter * 0.35,
                                        color: widget.color,
                                      )
                                    : Icon(
                                        Icons.bluetooth_searching_rounded,
                                        size: clampedDiameter * 0.38,
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                      ),
                      ),
                    ),
                  );
                },
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
