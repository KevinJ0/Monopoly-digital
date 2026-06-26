import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';
import 'package:monopoly_banking/screens/nfc_test_screen.dart';
import 'package:monopoly_banking/screens/ble_test_screen.dart';
import 'package:monopoly_banking/screens/player_discovery_screen.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/network_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/transports/ble_transport.dart';
import 'package:monopoly_banking/services/transports/nfc_transport.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/odometer_widget.dart';
import 'package:monopoly_banking/widgets/premium_dialog.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:monopoly_banking/widgets/transport_selector.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseCtrl;
  late final AnimationController _welcomeCtrl;
  late final Animation<double> _welcomeScale;
  late final Animation<double> _welcomeOpacity;
  late final ConfettiController _confettiCtrl;

  bool _nfcListening = false;
  bool _showWelcome = false;
  bool _isBankruptOverlayActive = false;
  DateTime? _lastBackPressTime;
  bool _isExiting = false;
  StreamSubscription<Map<String, dynamic>>? _payloadSub;
  StreamSubscription<TxType>? _txSub;
  StreamSubscription<CardTier>? _tierSub;
  bool _nfcLoopRunning = false;
  bool _bleScanning = false;
  final Set<String> _seenTxIds = <String>{};
  final List<String> _seenTxIdOrder = <String>[];
  VoidCallback? _bankruptListener;

  String? _lastRole;
  Color? _lastColor;
  String? _lastName;
  String? _lastAvatarId;
  int? _lastColorId;
  double? _lastBalance;
  final List<double> _lastHistory = [];

  late final VoidCallback _typeListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _welcomeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _welcomeScale =
        CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeOutBack);
    _welcomeOpacity =
        CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeIn);

    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));

    _listenForIncoming();

    _typeListener = () {
      if (P2PService().currentType != TransportType.ble && _bleScanning) {
        _stopBleClient();
      }
    };
    P2PService().typeNotifier.addListener(_typeListener);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<SessionProvider>();
      await P2PService().initTransports(isBank: session.isBank);
      _listenToBankruptcy();
      _listenToTierEvolution();
      _connectToHost(session);
      if (session.isBank) {
        await _ensureBankBleServerActive();
      } else {
        _startNfcLoop();
      }
    });
  }

  void _connectToHost(SessionProvider session) {
    if (!session.isBank) {
      JugadorClient().connect({
        'USUARIOID': session.name,
        'TREVNOT': context.read<WalletController>().rawBalance.value,
        'avatar': session.avatarId,
        'color': session.colorId,
      }).catchError((e, s) {
        if (mounted) context.showFriendlyError(e, s);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = context.read<SessionProvider>();
      if (session.isBank) {
        _ensureBankBleServerActive();
      } else {
        _startNfcLoop();
      }
    } else if (state == AppLifecycleState.paused) {
      _stopNfcLoop();
    }
  }

  void _listenForIncoming() {
    final wallet = context.read<WalletController>();
    final session = context.read<SessionProvider>();

    _payloadSub ??= P2PService().payloadStream.listen((payload) async {
      if (!mounted) return;
      final txId = payload['txId'] as String?;
      if (txId != null) {
        if (_seenTxIds.contains(txId)) return;
        _seenTxIds.add(txId);
        _seenTxIdOrder.add(txId);
        if (_seenTxIdOrder.length > 80) {
          final removed = _seenTxIdOrder.removeAt(0);
          _seenTxIds.remove(removed);
        }
      }
      final type = payload['type'] as String?;

      if (type == 'handshake') {
        if (!session.isHandshakeDone) {
          await session.applyHandshake(payload);
          _triggerWelcomeAnimation(payload['name'] as String?);
          P2PService().sendPayload({
            'type': 'handshake_confirm',
            'name': session.name,
          });
        }
      } else if (type == 'handshake_confirm') {
        final name = payload['name'] as String? ?? 'Jugador';
        _showToast('$name se ha unido a la partida', kGold);
      } else if (type == 'payment') {
        final amount = (payload['amount'] as num).toDouble();
        wallet.addFunds(amount);
        _showToast('¡Recibiste ${formatMoney(amount)}!', kGreen);
      } else if (type == 'charge') {
        final amount = (payload['amount'] as num).toDouble();
        wallet.subtractFunds(amount);
        _showToast('Te cobraron ${formatMoney(amount)}', kRed);
      } else if (type == 'passGo') {
        wallet.addFunds(kPassGoAmount, isPassGo: true);
        _showToast('Pasaste por GO: +${formatMoney(kPassGoAmount)}', kGold);
      }
    }, onError: (e, s) {
      if (mounted) context.showFriendlyError(e, s);
    });
  }

  void _startNfcLoop() {
    if (_nfcLoopRunning) return;
    final currentTransport = P2PService().currentType;
    if (currentTransport == TransportType.ble) return;
    _nfcLoopRunning = true;
    _runNfcOnce();
  }

  void _stopNfcLoop() {
    _nfcLoopRunning = false;
  }

  Future<void> _ensureBankBleServerActive() async {
    final transport = P2PService().bleTransport;
    final ready = await _ensureBleReady(transport);
    if (!ready || !mounted) return;
    await transport.startServer();
    P2PService().setTransport(TransportType.ble);
  }

  Future<void> _runNfcOnce() async {
    if (!mounted || !_nfcLoopRunning) {
      _nfcLoopRunning = false;
      return;
    }
    try {
      await P2PService().startReceiving(null);
    } catch (e, s) {
      if (!mounted || !_nfcLoopRunning) {
        _nfcLoopRunning = false;
        return;
      }
      if (mounted) context.showFriendlyError(e, s);
    }
    if (_nfcLoopRunning && mounted) {
      await Future.delayed(const Duration(milliseconds: 800));
      _runNfcOnce();
    } else {
      _nfcLoopRunning = false;
    }
  }

  Future<void> _startBleClient() async {
    if (_bleScanning) return;
    if (P2PService().currentType != TransportType.ble) {
      P2PService().setTransport(TransportType.ble);
    }
    _bleScanning = true;
    setState(() {});
    try {
      await P2PService().startReceiving(null);
    } catch (e, s) {
      _bleScanning = false;
      if (mounted) setState(() {});
      if (mounted) context.showFriendlyError(e, s);
    }
  }

  void _stopBleClient() {
    _bleScanning = false;
    P2PService().bleTransport.stopClientScan();
    if (mounted) setState(() {});
  }

  Future<void> _connectToBleBank(BleBankDevice bank) async {
    SoundService.playClick();
    _bleScanning = false;
    if (mounted) setState(() {});
    try {
      await P2PService().bleTransport.connectToBank(bank);
    } catch (e, s) {
      if (mounted) context.showFriendlyError(e, s);
    }
  }

  void _listenToBankruptcy() {
    final wallet = context.read<WalletController>();
    _bankruptListener ??= () {
      if (wallet.bankruptNotifier.value && mounted) {
        _showBankruptcyOverlay();
      }
    };
    wallet.bankruptNotifier.addListener(_bankruptListener!);

    _txSub?.cancel();
    _txSub = wallet.txStream.listen((event) {
      if (event == TxType.largeTransfer && mounted) {
        _confettiCtrl.play();
      }
    });
  }

  Future<void> _showNfcDisabledDialog() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NFC desactivado'),
        content: const Text(
            'Para usar la app necesitas NFC. ¿Quieres activarlo ahora?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _showToast('Abriendo ajustes de NFC...', kGold);
      await Future.delayed(const Duration(milliseconds: 600));
      final nfcTransport =
          P2PService().transports[TransportType.nfc] as NfcTransport?;
      await nfcTransport?.openNfcSettings();
    } else {
      _showToast('NFC necesario para continuar', Colors.red);
    }
  }

  void _showToast(String msg, Color color) {
    NotificationService().show(msg, backgroundColor: color);
  }

  void _listenToTierEvolution() {
    final wallet = context.read<WalletController>();
    _tierSub?.cancel();
    _tierSub = wallet.tierStream.listen((newTier) {
      if (mounted) {
        _showEvolutionAnimation(newTier);
      }
    });
  }

  void _showEvolutionAnimation(CardTier tier) async {
    // Pokemon-style evolution feel
    HapticFeedback.vibrate();
    SoundService.playSuccess();

    String tierName = "";
    Color accentColor = Colors.white;
    switch (tier) {
      case CardTier.gold:
        tierName = "GOLD";
        accentColor = const Color(0xFFBF953F);
        break;
      case CardTier.platinum:
        tierName = "PLATINUM";
        accentColor = const Color(0xFFE0E0E0);
        break;
      case CardTier.black:
        tierName = "ULTIMATE BLACK";
        accentColor = Colors.blueAccent;
        break;
      default:
        tierName = "STANDARD";
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (ctx, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AnimatedEntry(
                  delay: Duration(milliseconds: 200),
                  child: Text(
                    "¡TU TARJETA ESTÁ EVOLUCIONANDO!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4),
                  ),
                ),
                const SizedBox(height: 40),
                ScaleTransition(
                  scale: Tween<double>(begin: 0.5, end: 1.2).animate(
                      CurvedAnimation(parent: anim1, curve: Curves.elasticOut)),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: accentColor.withValues(alpha: 0.5),
                            blurRadius: 50,
                            spreadRadius: 10)
                      ],
                    ),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 120, color: accentColor),
                  ),
                ),
                const SizedBox(height: 40),
                AnimatedEntry(
                  delay: const Duration(milliseconds: 600),
                  child: Column(
                    children: [
                      const Text(
                        "¡FELICIDADES!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "HAS ALCANZADO EL NIVEL $tierName",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: accentColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                ElevatedButton(
                  onPressed: () {
                    _confettiCtrl.play();
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text("VER MI NUEVA TARJETA",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
  }

  void _showBankruptcyOverlay() {
    setState(() {
      _isBankruptOverlayActive = true;
    });
  }

  Future<void> _toggleNfc() async {
    setState(() {
      _nfcListening = !_nfcListening;
      if (_nfcListening) {
        _pulseCtrl.reset();
        _pulseCtrl.repeat();
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.reset();
      }
    });
  }

  Future<void> _triggerWelcomeAnimation(String? name) async {
    setState(() {
      _showWelcome = true;
    });
    await _welcomeCtrl.forward();
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      await _welcomeCtrl.reverse();
      setState(() => _showWelcome = false);
    }
  }

  Future<void> _hideWelcome() async {
    if (_showWelcome) {
      await _welcomeCtrl.reverse();
      setState(() => _showWelcome = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopNfcLoop();
    _stopBleClient();
    P2PService().shutdown();
    _payloadSub?.cancel();
    _txSub?.cancel();
    _tierSub?.cancel();
    final bankruptListener = _bankruptListener;
    if (bankruptListener != null) {
      context.read<WalletController>().bankruptNotifier.removeListener(
            bankruptListener,
          );
    }
    P2PService().typeNotifier.removeListener(_typeListener);
    _pulseCtrl.dispose();
    _welcomeCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final session = context.watch<SessionProvider>();
    final stats = context.watch<StatsProvider>();
    final history = wallet.history;

    if (session.role.isNotEmpty && !_isExiting) {
      _lastRole = session.role;
      _lastColor = session.color;
      _lastName = session.name;
      _lastAvatarId = session.avatarId;
      _lastColorId = int.tryParse(session.colorId) ?? 0;
      _lastBalance = wallet.rawBalance.value;
    }

    final displayColor = _lastColor ?? kGreen;
    final displayName = _lastName ?? '';
    final displayAvatar = _lastAvatarId ?? '';
    final displayRole = _lastRole ?? 'cliente';
    final displayColorId = _lastColorId ?? 0;
    final displayBalance = _lastBalance ?? 0.0;
    final isBank = displayRole == 'banco';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          NotificationService().show(
            'Presiona Atrás de nuevo para salir',
            backgroundColor: Colors.black87,
            duration: const Duration(seconds: 2),
          );
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: kBgDark,
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Botón de TEST (+200 GO)
            if (!isBank)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FloatingActionButton.small(
                  heroTag: 'test_go_btn',
                  onPressed: () {
                    SoundService.playClick();
                    wallet.addFunds(kPassGoAmount, isPassGo: true);
                    _showToast(
                        'TEST: +${formatMoney(kPassGoAmount)} (GO)', kGold);
                  },
                  backgroundColor: Colors.white10,
                  foregroundColor: kGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white10),
                  ),
                  child: const Icon(Icons.plus_one_rounded),
                ),
              ),
            isBank
                ? FloatingActionButton.extended(
                    heroTag: 'bank_panel_btn',
                    onPressed: () async {
                      SoundService.playClick();
                      _stopNfcLoop();
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BankScreen()),
                      );
                      if (mounted) await _ensureBankBleServerActive();
                    },
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                    icon: const Icon(Icons.account_balance_rounded),
                    label: const Text(
                      'Panel Banco',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  )
                : FloatingActionButton.extended(
                    heroTag: 'transfer_btn',
                    onPressed: () {
                      SoundService.playClick();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PlayerDiscoveryScreen()),
                      );
                    },
                    backgroundColor: displayColor,
                    foregroundColor: displayColor.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                    icon: const Icon(Icons.people_alt_rounded),
                    label: const Text(
                      'Transferir',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: PlayerColorBackdrop(
          color: displayColor,
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: CustomScrollView(
                    slivers: [
                      _buildAppBar(displayAvatar, displayColor, displayName,
                          displayRole, isBank),
                      SliverToBoxAdapter(
                        child: AnimatedEntry(
                          delay: const Duration(milliseconds: 100),
                          child: _buildBalanceCard(
                              displayBalance,
                              displayColor,
                              displayName,
                              displayColorId,
                              _lastHistory,
                              isBank),
                        ),
                      ),
                      if (!isBank)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 200),
                            child: _buildVaultSection(wallet, displayColor),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: AnimatedEntry(
                          delay: const Duration(milliseconds: 300),
                          child: _buildStatsRow(stats, displayColor),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: AnimatedEntry(
                          delay: const Duration(milliseconds: 400),
                          child: ValueListenableBuilder<TransportType>(
                            valueListenable: P2PService().typeNotifier,
                            builder: (context, type, _) {
                              return _buildConnectionPanel(
                                  displayColor, type, isBank);
                            },
                          ),
                        ),
                      ),
                      if (isBank)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 450),
                            child: _buildConnectedPlayersPanel(displayColor),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: TransportSelector(),
                        ),
                      ),
                      if (!isBank)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: StreamBuilder<Map<String, dynamic>>(
                              stream: JugadorClient().messages,
                              builder: (context, snapshot) {
                                if (snapshot.hasData &&
                                    snapshot.data!['type'] ==
                                        'transfer_state') {
                                  final stateStr = snapshot.data!['state'];
                                  return _buildNetworkTransferAlert(
                                      stateStr, displayName, isBank);
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: AnimatedEntry(
                          delay: const Duration(milliseconds: 500),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                            child: Row(
                              children: [
                                const Text(
                                  'HISTORIAL',
                                  style: TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 12,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: kBgCard,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${history.length}',
                                    style: const TextStyle(
                                        color: kTextSecondary, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (history.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_rounded,
                                    color: Color(0xFF4B5563), size: 48),
                                SizedBox(height: 12),
                                Text(
                                  'Sin transacciones aún',
                                  style: TextStyle(color: kTextSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => TransactionTile(tx: history[i]),
                            childCount: history.length,
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                            height: 80 + MediaQuery.of(context).padding.bottom),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiCtrl,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [kGold, kGreen, Colors.white, Colors.blue],
                  numberOfParticles: 50,
                  gravity: 0.1,
                ),
              ),
              if (_isBankruptOverlayActive)
                _buildBankruptcyScreen(displayName, session),
              if (_showWelcome)
                _buildWelcomeOverlay(displayAvatar, displayColor, displayName),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkTransferAlert(
      String stateStr, String userName, bool isBank) {
    Color color = kGold;
    String label = '';
    String sub = '';
    bool showAction = false;

    if (stateStr == 'waitingSender' && !isBank) {
      color = kRed;
      label = 'EMISOR: ENTREGAR DINERO';
      sub = 'Toca para confirmar el envío al banco';
      showAction = true;
    } else if (stateStr == 'waitingReceiver' && !isBank) {
      color = kGreen;
      label = 'RECEPTOR: RECIBIR DINERO';
      sub = 'Dinero listo en el banco. Toca para cobrar';
      showAction = true;
    } else if (stateStr == 'holding') {
      color = kGold;
      label = 'DINERO RETENIDO EN BANCO';
      sub = 'Procesando transferencia...';
    } else {
      return const SizedBox();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.2)),
                    Text(sub,
                        style: const TextStyle(
                            color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (showAction) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  SoundService.playClick();
                  try {
                    JugadorClient().confirmAction(userName);
                  } catch (e, s) {
                    if (context.mounted) context.showFriendlyError(e, s);
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.black),
                child: const Text('CONFIRMAR ACCIÓN FÍSICA',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBankruptcyScreen(String name, SessionProvider session) {
    return Container(
      color: Colors.black.withValues(alpha: 0.95),
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 1),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            child:
                const Icon(Icons.broken_image_rounded, color: kRed, size: 120),
          ),
          const SizedBox(height: 32),
          const Text(
            '¡BANCARROTA!',
            style: TextStyle(
              color: kRed,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            child: Text(
              'Has perdido todo tu dinero. El banco ha confiscado tus propiedades y cerrado tus cuentas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary, fontSize: 16),
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () {
              SoundService.playClick();
              session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text(
              'RECOGER MIS TABLAS E IRME',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              SoundService.playClick();
              setState(() => _isBankruptOverlayActive = false);
            },
            child: const Text(
              'Ver mis deudas (Cerrar)',
              style: TextStyle(color: Colors.white24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeOverlay(String avatarId, Color color, String name) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: FadeTransition(
          opacity: _welcomeOpacity,
          child: ScaleTransition(
            scale: _welcomeScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: color.withValues(alpha: 0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: Text(
                    avatarId,
                    style: const TextStyle(fontSize: 80),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '¡BIENVENIDO!',
                  style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 48),
                IconButton(
                  onPressed: () {
                    SoundService.playClick();
                    _hideWelcome();
                  },
                  icon: const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 64),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(
      String avatarId, Color color, String name, String role, bool isBank) {
    final width = MediaQuery.sizeOf(context).width;
    final compactActions = width < 390;
    final title =
        isBank ? 'Banca Central' : (name.isNotEmpty ? name : 'Mi Billetera');
    final subtitle =
        role.toLowerCase() == 'cliente' ? 'JUGADOR' : role.toUpperCase();

    return SliverAppBar(
      backgroundColor: kBgDark,
      expandedHeight: 0,
      floating: true,
      leadingWidth: 0,
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: compactActions ? 32 : 36,
            height: compactActions ? 32 : 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(
                avatarId,
                overflow: TextOverflow.clip,
                style: TextStyle(fontSize: compactActions ? 16 : 18),
              ),
            ),
          ),
          SizedBox(width: compactActions ? 8 : 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kTextPrimary,
                    fontSize: compactActions ? 14 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!compactActions) ...[
          IconButton(
            icon: const Icon(Icons.nfc_rounded, color: kTextSecondary),
            tooltip: 'NFC Debug',
            onPressed: _openNfcDebug,
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_rounded, color: kTextSecondary),
            tooltip: 'BLE Debug',
            onPressed: _openBleDebug,
          ),
        ],
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: kRed),
          tooltip: 'Cerrar Sesión',
          onPressed: () {
            SoundService.playClick();
            _confirmExit(context.read<SessionProvider>());
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
          onPressed: () {
            SoundService.playClick();
            setState(() {});
          },
        ),
        if (compactActions)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: kTextSecondary),
            tooltip: 'Más opciones',
            color: kBgCard,
            onSelected: (value) {
              if (value == 'nfc') _openNfcDebug();
              if (value == 'ble') _openBleDebug();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'nfc',
                child: Text('NFC Debug'),
              ),
              PopupMenuItem(
                value: 'ble',
                child: Text('BLE Debug'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _openNfcDebug() async {
    SoundService.playClick();
    _stopNfcLoop();
    await P2PService().shutdown();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NfcTestScreen()),
    );
    if (mounted) _startNfcLoop();
  }

  Future<void> _openBleDebug() async {
    SoundService.playClick();
    _stopNfcLoop();
    await P2PService().shutdown();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BleTestScreen()),
    );
    if (mounted) _startNfcLoop();
  }

  void _confirmExit(SessionProvider session) {
    showPremiumDialog(
      context: context,
      child: AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cerrar sesión?',
            style: TextStyle(color: kTextPrimary)),
        content: const Text(
          'Se borrarán todos los datos de esta partida y volverás a la selección de roles.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(context);
            },
            child:
                const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _isExiting = true);
              Navigator.pop(context);
              session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(double balance, Color color, String name,
      int colorId, List<double> history, bool isBank) {
    if (isBank) {
      return _buildBankDisplay(balance);
    }
    return _PremiumCreditCard(
      balance: balance,
      name: name,
      color: color,
      colorId: colorId,
      history: history,
      isBank: isBank,
    );
  }

  Widget _buildVaultSection(WalletController wallet, Color color) {
    return ValueListenableBuilder<double>(
        valueListenable: wallet.vaultInvestedAmount,
        builder: (context, invested, _) {
          return ValueListenableBuilder<double>(
              valueListenable: wallet.vaultGeneratedAmount,
              builder: (context, generated, _) {
                return ValueListenableBuilder<int>(
                    valueListenable: wallet.vaultCurrentPasses,
                    builder: (context, currentPasses, _) {
                      return ValueListenableBuilder<int>(
                          valueListenable: wallet.vaultTargetPasses,
                          builder: (context, targetPasses, _) {
                            final hasInvestment = invested > 0;
                            return Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: kBgCard,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.security_rounded,
                                          color: Colors.blueGrey),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'BÓVEDA DE INVERSIÓN',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (hasInvestment)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: targetPasses > 0 &&
                                                    currentPasses >=
                                                        targetPasses
                                                ? kGreenGlow.withValues(
                                                    alpha: 0.2)
                                                : Colors.orange
                                                    .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            targetPasses > 0 &&
                                                    currentPasses >=
                                                        targetPasses
                                                ? 'COMPLETADO'
                                                : 'EN PROCESO',
                                            style: TextStyle(
                                              color: targetPasses > 0 &&
                                                      currentPasses >=
                                                          targetPasses
                                                  ? kGreenGlow
                                                  : Colors.orange,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (!hasInvestment) ...[
                                    const Text(
                                      'Invierta su dinero a plazo fijo. Obtenga altos retornos bloqueando su saldo por una determinada cantidad de cruces por GO.',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          SoundService.playClick();
                                          _showInvestDialog(wallet, color);
                                        },
                                        icon: const Icon(
                                            Icons.rocket_launch_rounded),
                                        label: const Text('Comenzar Inversión'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: color,
                                          foregroundColor:
                                              color.computeLuminance() > 0.5
                                                  ? Colors.black
                                                  : Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                      ),
                                    )
                                  ] else ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Capital Invertido',
                                                style: TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11)),
                                            Text(formatMoney(invested),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 20,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text('Rendimiento',
                                                style: TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11)),
                                            Text('+${formatMoney(generated)}',
                                                style: const TextStyle(
                                                    color: kGreenGlow,
                                                    fontSize: 20,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: targetPasses > 0
                                                  ? (currentPasses /
                                                          targetPasses)
                                                      .clamp(0.0, 1.0)
                                                  : 0.0,
                                              minHeight: 8,
                                              backgroundColor: Colors.white10,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '$currentPasses / $targetPasses GO',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          SoundService.playClick();
                                          _showWithdrawDialog(wallet);
                                        },
                                        icon: const Icon(Icons
                                            .account_balance_wallet_rounded),
                                        label: Text(currentPasses >=
                                                targetPasses
                                            ? 'Retirar Ganancias'
                                            : 'Retirar Anticipadamente (Penalidad 20%)'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              currentPasses >= targetPasses
                                                  ? kGreenGlow
                                                  : kRed,
                                          side: BorderSide(
                                              color:
                                                  currentPasses >= targetPasses
                                                      ? kGreenGlow
                                                      : kRed),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                      ),
                                    )
                                  ],
                                ],
                              ),
                            );
                          });
                    });
              });
        });
  }

  void _showInvestDialog(WalletController wallet, Color brandColor) {
    final amountCtrl = TextEditingController();
    int selectedPasses = 3;

    showPremiumDialog(
      context: context,
      child: StatefulBuilder(builder: (context, setStateSB) {
        final val = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
        double getRate(int passes) {
          switch (passes) {
            case 1:
              return 0.05;
            case 2:
              return 0.07;
            case 3:
              return 0.10;
            case 4:
              return 0.12;
            case 5:
              return 0.15;
            default:
              return 0.05;
          }
        }

        final rate = getRate(selectedPasses);
        final expectedTotal = val > 0 ? val * rate * selectedPasses : 0;

        return AlertDialog(
          backgroundColor: kBgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nueva Inversión',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Monto a Invertir',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setStateSB(() {}),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    filled: true,
                    fillColor: kBgDark,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Plazo (Pases por GO)',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (index) {
                    final passes = index + 1;
                    final isSelected = selectedPasses == passes;
                    return GestureDetector(
                      onTap: () {
                        SoundService.playClick();
                        setStateSB(() => selectedPasses = passes);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? brandColor : kBgDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isSelected ? brandColor : Colors.white10),
                        ),
                        child: Text(
                          '$passes',
                          style: TextStyle(
                            color: isSelected
                                ? (brandColor.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white)
                                : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('Rendimiento por Pase: ${(rate * 100).round()}%',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('Ganancia Estimada: ${formatMoney(expectedTotal)}',
                          style: const TextStyle(
                              color: kGreenGlow,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  SoundService.playClick();
                  Navigator.pop(context);
                },
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                foregroundColor: brandColor.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
              onPressed: () {
                SoundService.playClick();
                final finalVal =
                    double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                if (finalVal > 0) {
                  if (wallet.balance < finalVal) {
                    _showToast(
                        'Saldo insuficiente para invertir ${formatMoney(finalVal)}',
                        kRed);
                    return;
                  }
                  try {
                    wallet.investInVault(finalVal, selectedPasses);
                    Navigator.pop(context);
                  } catch (e, s) {
                    if (context.mounted) context.showFriendlyError(e, s);
                  }
                }
              },
              child: const Text('Invertir'),
            ),
          ],
        );
      }),
    );
  }

  void _showWithdrawDialog(WalletController wallet) {
    final isEarly = wallet.currentPassesVault < wallet.targetPassesVault;
    showPremiumDialog(
        context: context,
        child: AlertDialog(
          backgroundColor: kBgCard,
          title: Text(isEarly ? 'Retiro Anticipado' : 'Retiro de Inversión',
              style: TextStyle(color: isEarly ? kRed : kGreenGlow)),
          content: Text(
            isEarly
                ? 'Aún no has cumplido los pases por GO (${wallet.currentPassesVault}/${wallet.targetPassesVault}). Si retiras ahora, perderás los intereses generados y se aplicará una penalización del 20% sobre tu capital invertido.\n\n¿Estás seguro que deseas retirar?'
                : '¡Enhorabuena! Has cumplido el plazo de tu inversión. Se acreditará tu capital más los intereses generados a tu cuenta principal.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  SoundService.playClick();
                  Navigator.pop(context);
                },
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: isEarly ? kRed : kGreenGlow,
                  foregroundColor: Colors.white),
              onPressed: () {
                SoundService.playClick();
                try {
                  wallet.withdrawVault();
                  Navigator.pop(context);
                } catch (e, s) {
                  if (context.mounted) context.showFriendlyError(e, s);
                }
              },
              child: Text(isEarly
                  ? 'Sí, Retirar con Penalización'
                  : 'Liquidar Inversión'),
            ),
          ],
        ));
  }

  Widget _buildBankDisplay(double balance) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: kBgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kGold.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 5,
          )
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_rounded, color: kGold, size: 48),
          const SizedBox(height: 16),
          const Text(
            'BÓVEDA DEL BANCO CENTRAL',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kGold,
              fontSize: 10,
              letterSpacing: 4,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          OdometerWidget(
            value: balance,
            color: kGold,
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: kGold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'TRANSACCIÓN AUTORIZADA',
              style: TextStyle(
                color: kGold,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(StatsProvider stats, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _StatChip(
            label: 'Volumen',
            value: _compact(stats.totalVolume),
            icon: Icons.payments_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Tx',
            value: stats.txCount.toString(),
            icon: Icons.history_rounded,
            color: color,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Pass GO',
            value: 'x${stats.passGoCount}',
            icon: Icons.flag_rounded,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel(
      Color color, TransportType currentTransport, bool isBank) {
    if (currentTransport == TransportType.ble) {
      if (isBank) return _buildBleBankPanel();
      return _buildBleClientPanel(color);
    }
    return _buildNfcButton(color);
  }

  Widget _buildConnectedPlayersPanel(Color color) {
    final transport = P2PService().bleTransport;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ValueListenableBuilder<List<BleConnectedPlayer>>(
        valueListenable: transport.connectedPlayersNotifier,
        builder: (context, blePlayers, _) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: BancoServer().connectedPlayers,
            initialData: const [],
            builder: (context, snapshot) {
              final wifiPlayers = snapshot.data ?? const [];
              final total = blePlayers.length + wifiPlayers.length;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBgCard.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.groups_rounded, color: color, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Jugadores conectados',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kTextPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '$total',
                          style: const TextStyle(
                            color: kTextSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (total == 0) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Sin jugadores activos',
                        style: TextStyle(color: kTextSecondary, fontSize: 12),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      ...blePlayers.map(_buildBleConnectedPlayerTile),
                      ...wifiPlayers.map(_buildWifiConnectedPlayerTile),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBleConnectedPlayerTile(BleConnectedPlayer player) {
    final detail = player.rssi == null
        ? player.qualityLabel
        : '${player.qualityLabel} - ${player.rssi} dBm';
    return _ConnectedPlayerTile(
      name: player.displayName,
      transport: 'BLE',
      detail: detail,
      color: player.qualityColor,
      icon: Icons.bluetooth_connected_rounded,
    );
  }

  Widget _buildWifiConnectedPlayerTile(Map<String, dynamic> player) {
    final name = (player['USUARIOID'] as String?)?.trim();
    return _ConnectedPlayerTile(
      name: name == null || name.isEmpty ? 'Jugador WiFi' : name,
      transport: 'WiFi',
      detail: (player['quality'] as String?) ?? 'Conectado',
      color: kGreen,
      icon: Icons.wifi_rounded,
    );
  }

  Future<bool> _ensureBleReady(BleTransport transport) async {
    var status = await transport.refreshAvailability();
    if (status == BleAvailabilityStatus.ready) return true;
    if (!mounted) return false;

    if (status == BleAvailabilityStatus.noHardware) {
      _showToast('Este dispositivo no tiene Bluetooth LE disponible.', kRed);
      return false;
    }

    if (status == BleAvailabilityStatus.missingPermissions) {
      final allow = await _confirmAction(
        title: 'Permisos de Bluetooth',
        message:
            'Para activar el servidor BLE del banco necesito permisos de Bluetooth. ¿Quieres permitirlos ahora?',
        confirmLabel: 'Permitir',
      );
      if (allow != true || !mounted) return false;

      await transport.requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));
      status = await transport.refreshAvailability();
      if (status == BleAvailabilityStatus.ready) return true;
      if (status == BleAvailabilityStatus.bluetoothOff) {
        return _askToOpenBleSettings(transport);
      }
      _showToast(
          'Permisos de Bluetooth pendientes. Revisa los permisos de la app.',
          kRed);
      return false;
    }

    if (status == BleAvailabilityStatus.bluetoothOff) {
      return _askToOpenBleSettings(transport);
    }

    _showToast(
        'No pude verificar Bluetooth. Revisa los ajustes e intenta de nuevo.',
        kRed);
    return false;
  }

  Future<bool> _askToOpenBleSettings(BleTransport transport) async {
    final open = await _confirmAction(
      title: 'Bluetooth apagado',
      message:
          'Para usar el banco por BLE debes activar Bluetooth. ¿Quieres abrir los ajustes?',
      confirmLabel: 'Abrir ajustes',
    );
    if (open == true && mounted) {
      await transport.openBleSettings();
    }
    return false;
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showBleDistanceSettings() {
    final transport = P2PService().bleTransport;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Configurar distancia',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800),
        ),
        content: ValueListenableBuilder<int>(
          valueListenable: transport.contactProfileIndexNotifier,
          builder: (context, index, _) {
            final profile = kBleContactProfiles[index];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.settings_input_antenna_rounded,
                        color: Colors.blue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        profile.label,
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  profile.helper,
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.blue,
                    inactiveTrackColor: kBorder,
                    thumbColor: kGold,
                    overlayColor: kGold.withValues(alpha: 0.12),
                    tickMarkShape:
                        const RoundSliderTickMarkShape(tickMarkRadius: 3),
                    activeTickMarkColor: kTextPrimary,
                    inactiveTickMarkColor: kTextSecondary,
                    valueIndicatorColor: kBgDark,
                    valueIndicatorTextStyle: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: (kBleContactProfiles.length - 1).toDouble(),
                    divisions: kBleContactProfiles.length - 1,
                    value: index.toDouble(),
                    label: profile.label,
                    onChanged: (value) {
                      SoundService.playClick();
                      transport.setContactProfileIndex(value.round());
                    },
                  ),
                ),
                const Row(
                  children: [
                    Text(
                      'Muy estricto',
                      style: TextStyle(color: kTextSecondary, fontSize: 11),
                    ),
                    Spacer(),
                    Text(
                      'Lejos',
                      style: TextStyle(color: kTextSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                SoundService.playClick();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Guardar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBleBankPanel() {
    final transport = P2PService().bleTransport;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: transport.serverActiveNotifier,
        builder: (context, active, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: transport.clientConnectedNotifier,
            builder: (context, connected, _) {
              return ValueListenableBuilder<String>(
                valueListenable: transport.connectionStatusNotifier,
                builder: (context, status, _) {
                  final accent = connected ? kGreen : Colors.blue;
                  final title = connected
                      ? 'JUGADOR CONECTADO'
                      : active
                          ? 'SERVIDOR BLE ACTIVO'
                          : 'SERVIDOR BLE';
                  final subtitle = status.isNotEmpty
                      ? status
                      : active
                          ? 'Esperando que un jugador se conecte...'
                          : 'Activa el servidor para recibir jugadores por Bluetooth';

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: active ? accent.withValues(alpha: 0.08) : kBgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            active ? accent.withValues(alpha: 0.45) : kBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connected
                                  ? Icons.bluetooth_connected_rounded
                                  : Icons.bluetooth_rounded,
                              color: active ? accent : kTextSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: active ? accent : kTextSecondary,
                                      fontSize: 11,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      color: kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active ? accent : kBorder,
                                boxShadow: active
                                    ? [
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                            if (active) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Configurar distancia',
                                onPressed: () {
                                  SoundService.playClick();
                                  _showBleDistanceSettings();
                                },
                                icon: const Icon(
                                  Icons.tune_rounded,
                                  color: kTextSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: active
                              ? Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        connected
                                            ? Icons.link_rounded
                                            : Icons.sensors_rounded,
                                        color: accent,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          connected
                                              ? 'Listo para operar con el jugador'
                                              : 'Activo automáticamente',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: accent,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () async {
                                    SoundService.playClick();
                                    final ready =
                                        await _ensureBleReady(transport);
                                    if (!ready || !mounted) return;
                                    await transport.startServer();
                                    P2PService()
                                        .setTransport(TransportType.ble);
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      size: 16),
                                  label: const Text('Iniciar Servidor BLE'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBleClientPanel(Color color) {
    final transport = P2PService().bleTransport;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: transport.clientConnectedNotifier,
        builder: (context, connected, _) {
          return ValueListenableBuilder<String>(
            valueListenable: transport.connectionStatusNotifier,
            builder: (context, status, _) {
              return ValueListenableBuilder<String>(
                valueListenable: transport.connectedDeviceNameNotifier,
                builder: (context, _, __) {
                  final connecting = status.startsWith('Conectando');
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          connected ? color.withValues(alpha: 0.08) : kBgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: connected
                            ? color.withValues(alpha: 0.5)
                            : connecting
                                ? Colors.blue.withValues(alpha: 0.4)
                                : _bleScanning
                                    ? Colors.blue.withValues(alpha: 0.4)
                                    : kBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connected
                                  ? Icons.bluetooth_connected_rounded
                                  : connecting
                                      ? Icons.bluetooth_searching_rounded
                                      : _bleScanning
                                          ? Icons.bluetooth_searching_rounded
                                          : Icons.bluetooth_rounded,
                              color: connected
                                  ? color
                                  : connecting
                                      ? Colors.blue
                                      : _bleScanning
                                          ? Colors.blue
                                          : kTextSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    connected
                                        ? 'CONECTADO AL BANCO'
                                        : connecting
                                            ? 'CONECTANDO AL BANCO...'
                                            : _bleScanning
                                                ? 'BUSCANDO SERVIDORES BLE...'
                                                : 'BLUETOOTH',
                                    style: TextStyle(
                                      color: connected
                                          ? color
                                          : connecting
                                              ? Colors.blue
                                              : _bleScanning
                                                  ? Colors.blue
                                                  : kTextSecondary,
                                      fontSize: 11,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (status.isNotEmpty)
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color: kTextSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected
                                    ? color
                                    : connecting
                                        ? Colors.blue
                                        : _bleScanning
                                            ? Colors.blue
                                            : kBorder,
                                boxShadow: (connected ||
                                        _bleScanning ||
                                        connecting)
                                    ? [
                                        BoxShadow(
                                          color:
                                              (connected ? color : Colors.blue)
                                                  .withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (!connected)
                          ValueListenableBuilder<List<BleBankDevice>>(
                            valueListenable: transport.discoveredBanksNotifier,
                            builder: (context, banks, _) {
                              if (!_bleScanning && banks.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (banks.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        'Esperando servidores activos...',
                                        style: TextStyle(
                                          color: kTextSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  else ...[
                                    const Text(
                                      'SERVIDORES DISPONIBLES',
                                      style: TextStyle(
                                        color: kTextSecondary,
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...banks.map(
                                      (bank) {
                                        final contactReady = transport
                                            .isRssiContactReady(bank.rssi);
                                        final bankColor =
                                            contactReady ? kGreen : Colors.blue;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: InkWell(
                                            onTap: () =>
                                                _connectToBleBank(bank),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: bankColor.withValues(
                                                    alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: bankColor.withValues(
                                                      alpha: 0.35),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .account_balance_rounded,
                                                    color: contactReady
                                                        ? kGreen
                                                        : Colors.blue,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          bank.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: kTextPrimary,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                        Text(
                                                          contactReady
                                                              ? 'En contacto para operaciones - ${bank.rssi} dBm'
                                                              : 'Conectable - acércalo al operar (${bank.rssi} dBm)',
                                                          style: TextStyle(
                                                            color: contactReady
                                                                ? kGreen
                                                                : Colors.blue,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Icon(
                                                    contactReady
                                                        ? Icons
                                                            .touch_app_rounded
                                                        : Icons
                                                            .bluetooth_connected_rounded,
                                                    color: contactReady
                                                        ? kGreen
                                                        : Colors.blue,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                ],
                              );
                            },
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: connected || _bleScanning || connecting
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    SoundService.playClick();
                                    _stopBleClient();
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_disabled_rounded,
                                      size: 16),
                                  label: Text(_bleScanning
                                      ? 'Cancelar Búsqueda'
                                      : 'Desconectar del Banco'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kRed,
                                    side: const BorderSide(color: kRed),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () {
                                    SoundService.playClick();
                                    _startBleClient();
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      size: 16),
                                  label: const Text('Buscar bancos BLE'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNfcButton(Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: GestureDetector(
        onTap: () {
          SoundService.playClick();
          _toggleNfc();
        },
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            return Container(
              height: 56,
              decoration: BoxDecoration(
                color: _nfcListening ? color.withValues(alpha: 0.05) : kBgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _nfcListening
                      ? color.withValues(
                          alpha: 0.3 + (0.7 * (1.0 - _pulseCtrl.value)))
                      : kBorder,
                  width: _nfcListening ? 2 : 1,
                ),
                gradient: _nfcListening
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.transparent,
                          color.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                        stops: [
                          (_pulseCtrl.value - 0.3).clamp(0.0, 1.0),
                          _pulseCtrl.value,
                          (_pulseCtrl.value + 0.3).clamp(0.0, 1.0),
                        ],
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _nfcListening
                        ? Icons.nfc_rounded
                        : Icons.sensors_off_rounded,
                    color: _nfcListening ? color : kTextSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _nfcListening
                        ? 'NFC ESCANEANDO...'
                        : 'ACTIVAR NFC / CONTACTLESS',
                    style: TextStyle(
                      color: _nfcListening ? color : kTextSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _compact(double val) {
    return formatMoney(val);
  }
}

class _PremiumCreditCard extends StatelessWidget {
  final double balance;
  final String name;
  final Color color;
  final int colorId;
  final List<double> history;
  final bool isBank;

  const _PremiumCreditCard({
    required this.balance,
    required this.name,
    required this.color,
    required this.colorId,
    required this.history,
    required this.isBank,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Ratio estándar de tarjeta de crédito: 85.6mm × 53.98mm = 1.586:1
      // Se capa a 240 para que en pantallas grandes (OnePlus 7T) sea igual que antes
      final cardHeight =
          ((constraints.maxWidth - 32) / 1.586).clamp(0.0, 240.0);

      // Special VIP Black Edition for Kevin and Meibi
      final nameLower = name.toLowerCase().trim();
      if (nameLower == 'kevin' || nameLower == 'meibi') {
        return _buildVipBlackCard(cardHeight: cardHeight);
      }

      final wallet = context.read<WalletController>();
      final tier = wallet.maxTier;
      final styles = _getStyles(tier, color);

      switch (tier) {
        case CardTier.standard:
          return _buildStandardCard(styles, cardHeight: cardHeight);
        case CardTier.gold:
          return _buildGoldCard(styles, cardHeight: cardHeight);
        case CardTier.platinum:
          return _buildPlatinumCard(styles, cardHeight: cardHeight);
        case CardTier.black:
          return _buildBlackCard(styles, cardHeight: cardHeight);
      }
    });
  }

  Widget _buildStandardCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: styles.gradient,
        boxShadow: [
          BoxShadow(
              color: styles.accent.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Stack(
        children: [
          Positioned(
              right: -30,
              top: -30,
              child: Icon(Icons.circle, size: 200, color: Colors.white10)),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.credit_card_rounded,
                        color: Colors.white70, size: 30),
                    Text(styles.tierName,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 4,
                          fontFamily: 'Courier')),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('JUGADOR',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 8)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('SALDO',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 8)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OdometerWidget(
                                  value: balance,
                                  color: Colors.white,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                              const SizedBox(width: 8),
                              _buildCardNetworkLogo(isVisa: true),
                            ],
                          ),
                        ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldCard(_CardStyles styles, {required double cardHeight}) {
    const goldLight = Color(0xFFFCF6BA);
    const goldDeep = Color(0xFFBF953F);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: styles.gradient,
        border: Border.all(color: goldLight.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
              color: goldDeep.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2)
        ],
      ),
      child: Stack(
        children: [
          Center(
              child: Opacity(
                  opacity: 0.1,
                  child:
                      Icon(Icons.stars_rounded, size: 200, color: goldLight))),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Text(styles.tierName,
                        style: TextStyle(
                            color: goldLight.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFF3E2723),
                          fontSize: 18,
                          letterSpacing: 4,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('GOLD MEMBER',
                                style: TextStyle(
                                    color: Color(0xFF5D4037),
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFF3E2723),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('SALDO DISPONIBLE',
                              style: TextStyle(
                                  color: Color(0xFF5D4037),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OdometerWidget(
                                  value: balance,
                                  color: const Color(0xFF3E2723),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF3E2723))),
                              const SizedBox(width: 8),
                              _buildCardNetworkLogo(isVisa: false),
                            ],
                          ),
                        ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatinumCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: styles.gradient,
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(
        children: [
          ...List.generate(
              15,
              (index) => Positioned(
                    left: index * 40.0,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child:
                        Container(color: Colors.white.withValues(alpha: 0.03)),
                  )),
          // Watermark effect
          Positioned(
            right: -20,
            bottom: 40,
            child: Transform.rotate(
              angle: -0.2,
              child: Opacity(
                opacity: 0.05,
                child: Text(
                  'PLATINUM\nPRESTIGE',
                  style: TextStyle(
                    color: const Color(0xFF102A43),
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    height: 0.8,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.wifi_rounded,
                            color: Color(0xFF486581), size: 24),
                        Text(styles.tierName,
                            style: const TextStyle(
                                color: Color(0xFF486581),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.5)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFF102A43),
                          fontSize: 22,
                          letterSpacing: 4.5,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PLATINUM CARDHOLDER',
                                style: TextStyle(
                                    color: Color(0xFF486581),
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFF102A43),
                                    fontSize: 16,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('BALANCE DISPONIBLE',
                            style: TextStyle(
                                color: Color(0xFF486581),
                                fontSize: 7,
                                fontWeight: FontWeight.w900)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OdometerWidget(
                                value: balance,
                                color: const Color(0xFF102A43),
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF102A43))),
                            const SizedBox(width: 8),
                            _buildCardNetworkLogo(isVisa: true),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlackCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black,
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 5)
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CarbonFiberPainter())),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.alt_route_rounded,
                        color: Color(0xFFD4AF37), size: 32),
                    Text(styles.tierName,
                        style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4)),
                  ],
                ),
                const Spacer(),
                _buildEmvChipDesign(isBlack: true),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 20,
                          letterSpacing: 5,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis),
                            Text(_getRandomQuote(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.6),
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic)),
                          ]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OdometerWidget(
                            value: balance,
                            color: const Color(0xFFD4AF37),
                            style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFD4AF37))),
                        const SizedBox(width: 8),
                        _buildCardNetworkLogo(isVisa: false),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmvChipDesign({bool isBlack = false}) {
    return Container(
      width: 45,
      height: 35,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: isBlack
                ? [Colors.grey.shade800, Colors.grey.shade600]
                : [Colors.amber.shade200, Colors.amber.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isBlack ? Colors.white24 : Colors.amber.shade700, width: 1),
      ),
      child: Stack(
        children: [
          Center(child: Container(width: 45, height: 1, color: Colors.black12)),
          Center(child: Container(width: 1, height: 35, color: Colors.black12)),
        ],
      ),
    );
  }

  Widget _buildCardNetworkLogo({required bool isVisa}) {
    if (isVisa) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('VISA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              )),
          Container(width: 30, height: 2, color: Colors.amber),
        ],
      );
    } else {
      return SizedBox(
        width: 40,
        height: 25,
        child: Stack(
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  shape: BoxShape.circle),
            ),
            Positioned(
              left: 12,
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.8),
                    shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildVipBlackCard({required double cardHeight}) {
    const goldDeep = Color(0xFFBF953F);
    const goldLight = Color(0xFFFCF6BA);
    const goldMid = Color(0xFFD4AF37);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: goldMid, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: goldMid.withValues(alpha: 0.4),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: goldDeep.withValues(alpha: 0.2),
              blurRadius: 48,
              spreadRadius: -4),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
              right: -60,
              top: -60,
              child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        goldMid.withValues(alpha: 0.15),
                        Colors.transparent
                      ])))),
          Positioned(
              left: -40,
              bottom: -40,
              child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        goldDeep.withValues(alpha: 0.2),
                        Colors.transparent
                      ])))),
          Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MONOPOLY BANK',
                              style: TextStyle(
                                  color: goldLight,
                                  fontSize: 9,
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w800)),
                          const Text('VIP BLACK EDITION',
                              style: TextStyle(
                                  color: goldMid,
                                  fontSize: 8,
                                  letterSpacing: 2.5,
                                  fontWeight: FontWeight.w700)),
                        ]),
                    Icon(Icons.diamond_rounded, color: goldLight, size: 30),
                  ],
                ),
                const Spacer(),
                _buildEmvChipDesign(),
                const SizedBox(height: 12),
                Text(_generateCardNumber(name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Courier',
                        fontSize: 18,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PLATINUM CARDHOLDER',
                                style: TextStyle(color: goldDeep, fontSize: 7)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OdometerWidget(
                            value: balance,
                            color: goldLight,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: goldLight)),
                        const SizedBox(width: 8),
                        _buildCardNetworkLogo(isVisa: true),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _CardStyles _getStyles(CardTier tier, Color playerColor) {
    switch (tier) {
      case CardTier.standard:
        return _CardStyles(
          gradient: LinearGradient(
            colors: [
              playerColor,
              Color.lerp(playerColor, Colors.black, 0.4)!,
              Color.lerp(playerColor, Colors.black, 0.7)!
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'CLASSIC EDITION',
        );
      case CardTier.gold:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFBF953F),
              Color(0xFFFCF6BA),
              Color(0xFFB38728),
              Color(0xFFFBF5B7),
              Color(0xFFFBF5B7)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: const Color(0xFF2D2410),
          tierName: 'GOLD MEMBERSHIP',
        );
      case CardTier.platinum:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD), Color(0xFF757575)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'PLATINUM PRESTIGE',
        );
      case CardTier.black:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.blueAccent,
          tierName: 'ULTIMATE BLACK',
        );
    }
  }

  String _generateCardNumber(String source) {
    if (source.isEmpty) source = "JUGADOR";
    // Usar el nombre como semilla para Random
    final seed = source
        .split('')
        .fold<int>(0, (prev, char) => prev + char.codeUnitAt(0));
    final rand = Random(seed);

    String part() => (rand.nextInt(9000) + 1000).toString().padLeft(4, '0');
    return "${part()} ${part()} ${part()} ${part()}";
  }

  String _getRandomQuote() {
    final quotes = [
      "Tu sueldo es mi propina.",
      "Demasiado rico para tener gusto.",
      "Mi única Bill es Gates.",
      "Compré el banco para no esperar.",
      "No hablo idioma 'descuento'.",
      "Más burbujas que tu cuenta.",
      "El caviar es mi snack.",
      "Oro para mis lentes.",
    ];
    return quotes[name.length % quotes.length];
  }
}

class _CardStyles {
  final LinearGradient gradient;
  final Color accent;
  final String tierName;
  _CardStyles(
      {required this.gradient, required this.accent, required this.tierName});
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: kBgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kTextSecondary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedPlayerTile extends StatelessWidget {
  final String name;
  final String transport;
  final String detail;
  final Color color;
  final IconData icon;

  const _ConnectedPlayerTile({
    required this.name,
    required this.transport,
    required this.detail,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$transport - $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarbonFiberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double i = -size.height; i < size.width; i += 10) {
      canvas.drawLine(
          Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
