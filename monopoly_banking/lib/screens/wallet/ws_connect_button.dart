import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/core/game_transitions.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/transports/ws_models.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';

class WsConnectButton extends StatefulWidget {
  final Color color;
  final bool scanning;
  final bool clientConnected;
  final bool connecting;
  final VoidCallback? onStartWsClient;
  final VoidCallback? onStopWsClient;
  final void Function(String host, int port)? onConnectToBank;

  const WsConnectButton({
    super.key,
    required this.color,
    this.scanning = false,
    this.clientConnected = false,
    this.connecting = false,
    this.onStartWsClient,
    this.onStopWsClient,
    this.onConnectToBank,
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
  bool _showManual = false;

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
    _ipCtrl.addListener(_onIpChanged);
  }

  void _onIpChanged() {
    if (mounted) setState(() {});
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

  void _scanQr() {
    SoundService.playClick();
    Navigator.of(context).push<void>(
      GameFadeRoute(
        page: _QrScannerPage(
          onScan: (ip, port) {
            widget.onConnectToBank?.call(ip, port);
          },
        ),
      ),
    );
  }

  void _scanMobile() {
    SoundService.playClick();
    Navigator.of(context).push<void>(
      GameFadeRoute(
        page: _MobileScannerPage(
          onScan: (ip, port) {
            widget.onConnectToBank?.call(ip, port);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final diameter = size.shortestSide * 0.45;
    final clampedDiameter = diameter.clamp(140.0, 220.0);
    final isActive =
        widget.scanning || widget.clientConnected || widget.connecting;

    final content = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                            colors: widget.connecting ||
                                    widget.scanning ||
                                    widget.clientConnected
                                ? [
                                    widget.color,
                                    widget.color.withValues(alpha: 0.45),
                                  ]
                                : [
                                    Colors.blue.withValues(alpha: 0.45),
                                    Colors.blue.withValues(alpha: 0.2),
                                  ],
                          ),
                          border: Border.all(
                            color: (isActive ? widget.color : Colors.white)
                                .withValues(alpha: 0.35),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isActive ? widget.color : Colors.blue)
                                  .withValues(alpha: 0.25),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: widget.connecting || widget.scanning || widget.clientConnected
                                  ? AppSpinner(
                                      size: clampedDiameter * 0.2,
                                      color: widget.color,
                                    )
                                  : Icon(
                                      Icons.wifi_find_rounded,
                                      size: clampedDiameter * 0.25,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.clientConnected
                    ? 'Esperando confirmación del banco...'
                    : widget.connecting
                        ? 'Conectando al banco...'
                        : widget.scanning
                            ? 'Buscando bancos en la red...'
                            : 'Tocar para buscar bancos disponibles',
                style: TextStyle(
                  color: widget.connecting || widget.scanning || widget.clientConnected
                      ? kTextSecondary
                      : kTextSecondary.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              if (widget.scanning) ...[
                ValueListenableBuilder<List<DiscoveredBank>>(
                  valueListenable:
                      P2PService().wsTransport.discoveredBanksNotifier,
                  builder: (context, banks, _) {
                    if (banks.isEmpty) return const SizedBox();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          'BANCOS DETECTADOS',
                          style: TextStyle(
                            color: kGold,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...banks.map((bank) => TweenAnimationBuilder<double>(
                              key: ValueKey('bank-${bank.ip}'),
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 20 * (1 - value)),
                                  child: GestureDetector(
                                    onTap: () {
                                      SoundService.playClick();
                                      widget.onConnectToBank
                                          ?.call(bank.ip, bank.port);
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: kBgCard,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: kBorder),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.wifi_tethering_rounded,
                                              color: kGreen, size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  bank.ip,
                                                  style: const TextStyle(
                                                    color: kTextPrimary,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Text(
                                                  'Puerto ${bank.port}',
                                                  style: const TextStyle(
                                                    color: kTextSecondary,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.touch_app_rounded,
                                              color: kTextSecondary, size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _scanQr,
                icon: const Icon(Icons.qr_code_rounded, size: 16),
                label: const Text(
                  'Escanear QR',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: _scanMobile,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: const Text(
                  'Escanear QR (v2)',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showManual = !_showManual),
                icon: Icon(
                  _showManual
                      ? Icons.expand_less_rounded
                      : Icons.settings_ethernet_rounded,
                  size: 16,
                ),
                label: Text(
                  _showManual
                      ? 'Ocultar conexión manual'
                      : 'Conexión manual',
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              if (widget.connecting || widget.clientConnected) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onStopWsClient?.call(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(
                        widget.clientConnected ? 'DESCONECTARSE' : 'CANCELAR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kTextSecondary,
                        side: BorderSide(color: kTextSecondary.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (_showManual) ...[
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
                    prefixIcon: const Icon(Icons.language_rounded,
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
                    onPressed: _ipCtrl.text.trim().isEmpty
                        ? null
                        : () {
                            final ip = _ipCtrl.text.trim();
                            final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;
                            widget.onConnectToBank?.call(ip, port);
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
            ],
          ),
        ),
      ),
    );

    return content;
  }
}

class _QrScannerPage extends StatefulWidget {
  final void Function(String ip, int port) onScan;
  const _QrScannerPage({required this.onScan});

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final GlobalKey _qrKey = GlobalKey();
  QRViewController? _qrController;

  @override
  void dispose() {
    _qrController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          QRView(
            key: _qrKey,
            onQRViewCreated: (controller) {
              _qrController = controller;
              controller.scannedDataStream.firstWhere(
                (barcode) =>
                    barcode.code != null &&
                    barcode.code!.startsWith('ws://'),
              ).then((barcode) {
                final uri = barcode.code!;
                final withoutScheme = uri.substring(5);
                final parts = withoutScheme.split(':');
                if (parts.isEmpty) return;
                final ip = parts[0];
                final port =
                    parts.length > 1 ? int.tryParse(parts[1]) ?? 8080 : 8080;
                Navigator.of(context).pop();
                widget.onScan(ip, port);
              });
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Escanea el código QR del banco',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileScannerPage extends StatefulWidget {
  final void Function(String ip, int port) onScan;
  const _MobileScannerPage({required this.onScan});

  @override
  State<_MobileScannerPage> createState() => _MobileScannerPageState();
}

class _MobileScannerPageState extends State<_MobileScannerPage> {
  MobileScannerController? _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null && barcode!.rawValue!.startsWith('ws://')) {
      _scanned = true;
      final withoutScheme = barcode.rawValue!.substring(5);
      final parts = withoutScheme.split(':');
      if (parts.isEmpty) return;
      final ip = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 8080 : 8080;
      Navigator.of(context).pop();
      widget.onScan(ip, port);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Escanea el código QR del banco',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
