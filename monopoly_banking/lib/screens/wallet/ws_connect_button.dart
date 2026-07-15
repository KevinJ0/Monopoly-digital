part of '../wallet_screen.dart';

class WsConnectButton extends StatefulWidget {
  final Color color;
  final bool scanning;
  final bool clientConnected;
  final bool connecting;
  final VoidCallback? onStartWsClient;
  final VoidCallback? onStopWsClient;

  const WsConnectButton({
    super.key,
    required this.color,
    this.scanning = false,
    this.clientConnected = false,
    this.connecting = false,
    this.onStartWsClient,
    this.onStopWsClient,
  });

  @override
  State<WsConnectButton> createState() => _WsConnectButtonState();
}

class _WsConnectButtonState extends State<WsConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8080');

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
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    SoundService.playClick();
    if (widget.clientConnected || widget.scanning || widget.connecting) {
      widget.onStopWsClient?.call();
    } else {
      widget.onStartWsClient?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final diameter = size.shortestSide * 0.45;
    final clampedDiameter = diameter.clamp(140.0, 220.0);
    final isActive =
        widget.scanning || widget.clientConnected || widget.connecting;

    if (widget.clientConnected) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: clampedDiameter,
                height: clampedDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color,
                      widget.color.withValues(alpha: 0.55),
                    ],
                  ),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.wifi_rounded,
                    size: clampedDiameter * 0.4,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'CONECTADO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Toca para desconectar',
                style: TextStyle(color: kTextSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _onTap,
                child: AnimatedBuilder(
                  animation: _scaleCtrl,
                  builder: (context, _) {
                    final scale = widget.connecting
                        ? 1.0
                        : widget.scanning
                            ? _scaleAnim.value
                            : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: clampedDiameter * 0.6,
                        height: clampedDiameter * 0.6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: widget.connecting
                                ? [
                                    widget.color,
                                    widget.color.withValues(alpha: 0.45),
                                  ]
                                : widget.scanning
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
                          child: widget.connecting
                              ? Icon(
                                  Icons.wifi_find_rounded,
                                  size: clampedDiameter * 0.25,
                                  color: Colors.white,
                                )
                              : widget.scanning
                                  ? AppSpinner(
                                      size: clampedDiameter * 0.2,
                                      color: widget.color,
                                    )
                                  : Icon(
                                      Icons.wifi_find_rounded,
                                      size: clampedDiameter * 0.25,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _ipCtrl,
                decoration: InputDecoration(
                  hintText: 'IP del banco (ej. 192.168.1.100)',
                  hintStyle: const TextStyle(color: kTextSecondary),
                  filled: true,
                  fillColor: kBgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.computer_rounded,
                      color: kTextSecondary),
                ),
                style: const TextStyle(color: kTextPrimary),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portCtrl,
                decoration: InputDecoration(
                  hintText: 'Puerto (8080)',
                  hintStyle: const TextStyle(color: kTextSecondary),
                  filled: true,
                  fillColor: kBgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.numbers_rounded,
                      color: kTextSecondary),
                ),
                style: const TextStyle(color: kTextPrimary),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final ip = _ipCtrl.text.trim();
                    final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;
                    if (ip.isEmpty) return;
                    widget.onStartWsClient?.call();
                    _self._connectToBank(ip, port: port);
                  },
                  icon: const Icon(Icons.link_rounded),
                  label: const Text(
                    'CONECTAR AL BANCO',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
