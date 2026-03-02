import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/network_service.dart';
import 'package:monopoly_banking/screens/player_discovery_screen.dart';
import 'package:monopoly_banking/widgets/odometer_widget.dart';
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with TickerProviderStateMixin {
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

  String? _lastRole;
  Color? _lastColor;
  String? _lastName;
  String? _lastAvatarId;
  int? _lastColorId;
  double? _lastBalance;
  final List<double> _lastHistory = [];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _welcomeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _welcomeScale = CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeOutBack);
    _welcomeOpacity = CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeIn);

    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));

    _listenForIncoming();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToBankruptcy();
      _connectToHost(context.read<SessionProvider>());
    });
  }

  void _connectToHost(SessionProvider session) {
    if (!session.isBank) {
      JugadorClient().connect({
        'USUARIOID': session.name,
        'TREVNOT': context.read<WalletController>().rawBalance.value,
        'avatar': session.avatarId,
        'color': session.colorId,
      }).catchError((e) {
        // Ignorar si el host no está levantado aún
      });
    }
  }

  void _listenForIncoming() {
    final wallet = context.read<WalletController>();
    final session = context.read<SessionProvider>();
    P2PService().startReceiving((payload) async {
      if (!mounted) return;
      final type = payload['type'] as String?;

      if (type == 'handshake') {
        if (!session.isHandshakeDone) {
          await session.applyHandshake(payload);
          _triggerWelcomeAnimation(payload['name'] as String?);
          // Confirm back to bank
          P2PService().sendPayload({
            'type': 'handshake_confirm',
            'name': session.name,
          });
        }
      } else if (type == 'handshake_confirm') {
        final name = payload['name'] as String? ?? 'Jugador';
        _showToast('✅ $name se ha unido a la partida', kGold);
      } else if (type == 'payment') {
        final amount = (payload['amount'] as num).toDouble();
        wallet.addFunds(amount);
        _showToast('¡Recibiste \$$amount!', kGreen);
      } else if (type == 'passGo') {
        wallet.addFunds(kPassGoAmount, isPassGo: true);
        _showToast('Pasaste por GO: +\$${kPassGoAmount.round()}', kGold);
      }
    });
  }

  void _listenToBankruptcy() {
    final wallet = context.read<WalletController>();
    wallet.bankruptNotifier.addListener(() {
      if (wallet.bankruptNotifier.value && mounted) {
        _showBankruptcyOverlay();
      }
    });

    wallet.txStream.listen((event) {
      if (event == TxType.largeTransfer && mounted) {
        _confettiCtrl.play();
      }
    });
  }

  void _showToast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
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
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Presiona Atrás de nuevo para salir',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.black87,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(20),
            ),
          );
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: kBgDark,
        floatingActionButton: isBank
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BankScreen()),
                ),
                backgroundColor: kGold,
                foregroundColor: Colors.black,
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text(
                  'Panel Banco',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerDiscoveryScreen()),
                ),
                backgroundColor: displayColor,
                foregroundColor: displayColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                icon: const Icon(Icons.people_alt_rounded),
                label: const Text(
                  'Transferir',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                _buildAppBar(displayAvatar, displayColor, displayName, displayRole, isBank),
                SliverToBoxAdapter(child: _buildBalanceCard(displayBalance, displayColor, displayName, displayColorId, _lastHistory, isBank)),
                if (!isBank) SliverToBoxAdapter(child: _buildVaultSection(wallet, displayColor)),
                SliverToBoxAdapter(child: _buildStatsRow(stats, displayColor)),
                SliverToBoxAdapter(child: _buildNfcButton(displayColor)),
                if (!isBank)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StreamBuilder<Map<String, dynamic>>(
                        stream: JugadorClient().messages,
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!['type'] == 'transfer_state') {
                            final stateStr = snapshot.data!['state'];
                            return _buildNetworkTransferAlert(stateStr, displayName, isBank);
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: kBgCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${history.length}',
                            style: const TextStyle(color: kTextSecondary, fontSize: 11),
                          ),
                        ),
                      ],
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
                          Icon(Icons.receipt_long_rounded, color: kBorder, size: 48),
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
              ],
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
            if (_isBankruptOverlayActive) _buildBankruptcyScreen(displayName, session),
            if (_showWelcome) _buildWelcomeOverlay(displayAvatar, displayColor, displayName),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkTransferAlert(String stateStr, String userName, bool isBank) {
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
                    Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                    Text(sub, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
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
                onPressed: () => JugadorClient().confirmAction(userName),
                style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black),
                child: const Text('CONFIRMAR ACCIÓN FÍSICA', style: TextStyle(fontWeight: FontWeight.bold)),
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
            child: const Icon(Icons.broken_image_rounded, color: kRed, size: 120),
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
              session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text(
              'RECOGER MIS TABLAS E IRME',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _isBankruptOverlayActive = false),
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
                    border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
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
                  onPressed: _hideWelcome,
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 64),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(String avatarId, Color color, String name, String role, bool isBank) {
    return SliverAppBar(
      backgroundColor: kBgDark,
      expandedHeight: 0,
      floating: true,
      leading: const SizedBox(),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Center(child: Text(avatarId, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isBank ? 'Banca Central' : (name.isNotEmpty ? name : 'Mi Billetera'),
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                role.toUpperCase(),
                style: const TextStyle(color: kTextSecondary, fontSize: 10, letterSpacing: 1),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: kRed),
          tooltip: 'Cerrar Sesión',
          onPressed: () => _confirmExit(context.read<SessionProvider>()),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
          onPressed: () => setState(() {}),
        ),
      ],
    );
  }

  void _confirmExit(SessionProvider session) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cerrar sesión?', style: TextStyle(color: kTextPrimary)),
        content: const Text(
          'Se borrarán todos los datos de esta partida y volverás a la selección de roles.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(double balance, Color color, String name, int colorId, List<double> history, bool isBank) {
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
                              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                                      const Icon(Icons.security_rounded, color: Colors.blueGrey),
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
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: targetPasses > 0 && currentPasses >= targetPasses
                                                ? kGreenGlow.withValues(alpha: 0.2)
                                                : Colors.orange.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            targetPasses > 0 && currentPasses >= targetPasses ? 'COMPLETADO' : 'EN PROCESO',
                                            style: TextStyle(
                                              color: targetPasses > 0 && currentPasses >= targetPasses ? kGreenGlow : Colors.orange,
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
                                      style: TextStyle(color: Colors.white54, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _showInvestDialog(wallet, color),
                                        icon: const Icon(Icons.rocket_launch_rounded),
                                        label: const Text('Comenzar Inversión'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: color,
                                          foregroundColor: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    )
                                  ] else ...[
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Capital Invertido', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                            Text('\$${invested.round()}',
                                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            const Text('Rendimiento', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                            Text('+\$${generated.round()}',
                                                style: const TextStyle(color: kGreenGlow, fontSize: 20, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: targetPasses > 0 ? (currentPasses / targetPasses).clamp(0.0, 1.0) : 0.0,
                                              minHeight: 8,
                                              backgroundColor: Colors.white10,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '$currentPasses / $targetPasses GO',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showWithdrawDialog(wallet),
                                        icon: const Icon(Icons.account_balance_wallet_rounded),
                                        label: Text(currentPasses >= targetPasses ? 'Retirar Ganancias' : 'Retirar Anticipadamente (Penalidad 20%)'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: currentPasses >= targetPasses ? kGreenGlow : kRed,
                                          side: BorderSide(color: currentPasses >= targetPasses ? kGreenGlow : kRed),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setStateSB) {
        final val = double.tryParse(amountCtrl.text) ?? 0;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nueva Inversión', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Monto a Invertir', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setStateSB(() {}),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    filled: true,
                    fillColor: kBgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Plazo (Pases por GO)', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (index) {
                    final passes = index + 1;
                    final isSelected = selectedPasses == passes;
                    return GestureDetector(
                      onTap: () => setStateSB(() => selectedPasses = passes),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? brandColor : kBgDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? brandColor : Colors.white10),
                        ),
                        child: Text(
                          '$passes',
                          style: TextStyle(
                            color: isSelected ? (brandColor.computeLuminance() > 0.5 ? Colors.black : Colors.white) : Colors.white54,
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
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('Rendimiento por Pase: ${(rate * 100).round()}%', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('Ganancia Estimada: \$${expectedTotal.round()}',
                          style: const TextStyle(color: kGreenGlow, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                foregroundColor: brandColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              ),
              onPressed: () {
                final finalVal = double.tryParse(amountCtrl.text) ?? 0;
                if (finalVal > 0) {
                  wallet.investInVault(finalVal, selectedPasses);
                  Navigator.pop(ctx);
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
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: kBgCard,
              title: Text(isEarly ? 'Retiro Anticipado' : 'Retiro de Inversión', style: TextStyle(color: isEarly ? kRed : kGreenGlow)),
              content: Text(
                isEarly
                    ? 'Aún no has cumplido los pases por GO (${wallet.currentPassesVault}/${wallet.targetPassesVault}). Si retiras ahora, perderás los intereses generados y se aplicará una penalización del 20% sobre tu capital invertido.\n\n¿Estás seguro que deseas retirar?'
                    : '¡Enhorabuena! Has cumplido el plazo de tu inversión. Se acreditará tu capital más los intereses generados a tu cuenta principal.',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: isEarly ? kRed : kGreenGlow, foregroundColor: Colors.white),
                  onPressed: () {
                    wallet.withdrawVault();
                    Navigator.pop(ctx);
                  },
                  child: Text(isEarly ? 'Sí, Retirar con Penalización' : 'Liquidar Inversión'),
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
            value: '×${stats.passGoCount}',
            icon: Icons.flag_rounded,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildNfcButton(Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: GestureDetector(
        onTap: _toggleNfc,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            return Container(
              height: 56,
              decoration: BoxDecoration(
                color: _nfcListening ? color.withValues(alpha: 0.05) : kBgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _nfcListening ? color.withValues(alpha: 0.3 + (0.7 * (1.0 - _pulseCtrl.value))) : kBorder,
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
                    _nfcListening ? Icons.nfc_rounded : Icons.sensors_off_rounded,
                    color: _nfcListening ? color : kTextSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _nfcListening ? 'NFC ESCANEANDO...' : 'ACTIVAR NFC / CONTACTLESS',
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
    if (val.isInfinite) return '∞';
    if (val.isNaN) return 'NaN';
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.round().toString();
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
    final tier = _getTier();
    final styles = _getStyles(tier);
    final isVisa = colorId % 2 == 0;

    if (isVisa) {
      return _buildVisaCard(styles, tier);
    } else {
      return _buildMastercardCard(styles, tier);
    }
  }

  Widget _buildMastercardCard(_CardStyles styles, _CardTier tier) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: styles.gradient,
        boxShadow: [
          BoxShadow(
            color: styles.accent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -50,
            child: CircleAvatar(
              radius: 100,
              backgroundColor: Colors.white.withValues(alpha: 0.03),
            ),
          ),
          if (history.isNotEmpty)
            Positioned(
              right: 0,
              left: 0,
              bottom: 0,
              top: 50,
              child: Opacity(
                opacity: 0.2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20, top: 20),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                          isCurved: true,
                          color: styles.accent,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [styles.accent.withValues(alpha: 0.3), styles.accent.withValues(alpha: 0.0)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          styles.tierName,
                          style: TextStyle(
                            color: styles.accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    _buildBrandLogo(colorId, false),
                  ],
                ),
                const Spacer(),
                Text(
                  isBank ? 'BANCO CENTRAL' : '**** **** **** ${1000 + colorId}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Courier',
                    fontSize: 16,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SALDO ACTUAL',
                            style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                          OdometerWidget(
                            value: balance,
                            color: Colors.white,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'VALIDEZ',
                          style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '12/30',
                          style: TextStyle(color: styles.accent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                if (tier == _CardTier.black) ...[
                  const SizedBox(height: 8),
                  Text(
                    _getRandomQuote(),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisaCard(_CardStyles styles, _CardTier tier) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Visa design typically uses strong solid colors or subtle gradients
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), Colors.black87],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background pattern for Visa
          Positioned.fill(
            child: CustomPaint(
              painter: _VisaBackgroundPattern(color: styles.accent.withValues(alpha: 0.1)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBrandLogo(colorId, true),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: styles.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: styles.accent.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        styles.tierName,
                        style: TextStyle(color: styles.accent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // EMV Chip
                Container(
                  width: 45,
                  height: 35,
                  decoration: BoxDecoration(
                      color: Colors.amber.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade600, width: 1.5),
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade200, Colors.amber.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )),
                  child: Stack(
                    children: [
                      Center(child: Container(width: 45, height: 1, color: Colors.amber.shade600)),
                      Center(child: Container(width: 1, height: 35, color: Colors.amber.shade600)),
                      Center(
                          child: Container(
                              width: 25,
                              height: 15,
                              decoration: BoxDecoration(border: Border.all(color: Colors.amber.shade600), borderRadius: BorderRadius.circular(4)))),
                    ],
                  ),
                ),
                Text(
                  isBank ? 'BANCO CENTRAL' : '4000 1234 5678 ${1000 + colorId}',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Courier',
                    fontSize: 22,
                    letterSpacing: 3,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 2)],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CARDHOLDER NAME',
                          style: TextStyle(color: Colors.white54, fontSize: 8, letterSpacing: 1),
                        ),
                        Text(
                          name.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('SALDO', style: TextStyle(color: Colors.white54, fontSize: 8)),
                        OdometerWidget(
                          value: balance,
                          color: Colors.white,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
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

  _CardTier _getTier() {
    if (isBank) return _CardTier.gold;
    if (balance >= 20000) return _CardTier.black;
    if (balance >= 10000) return _CardTier.platinum;
    if (balance >= 5000) return _CardTier.gold;
    return _CardTier.standard;
  }

  _CardStyles _getStyles(_CardTier tier) {
    switch (tier) {
      case _CardTier.standard:
        return _CardStyles(
          gradient: LinearGradient(
            colors: [
              color,
              Color.lerp(color, Colors.black, 0.4)!,
              Color.lerp(color, Colors.black, 0.7)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'CLASSIC EDITION',
        );
      case _CardTier.gold:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFFBF953F), Color(0xFFFCF6BA), Color(0xFFB38728), Color(0xFFFBF5B7), Color(0xFFAA771C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: const Color(0xFF2D2410),
          tierName: 'GOLD MEMBERSHIP',
        );
      case _CardTier.platinum:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD), Color(0xFF757575)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'PLATINUM PRESTIGE',
        );
      case _CardTier.black:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'ULTIMATE BLACK EDITION',
        );
    }
  }

  Widget _buildBrandLogo(int id, bool isVisa) {
    return Column(
      children: [
        Icon(
          isVisa ? Icons.credit_card_rounded : Icons.payments_rounded,
          color: Colors.white38,
          size: 32,
        ),
        Text(
          isVisa ? 'VISA' : 'Mastercard',
          style: const TextStyle(
            color: Colors.white38,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  String _getRandomQuote() {
    final quotes = [
      "Mi jet tiene su propia pista de aterrizaje.",
      "¿Ahorrar? Pensé que eso era un deporte extremo.",
      "Uso billetes de 500 para limpiar mis gafas.",
      "Mis propinas son el salario anual de una nación.",
      "Este café costó lo mismo que tu primer coche.",
      "Perdí un Rolex en el sofá y simplemente compré otro sofá.",
      "El oro es mi color favorito, después del platino.",
      "No hablo el idioma de los descuentos.",
      "Mi champán tiene más burbujas que tu cuenta.",
      "Contraté a alguien para que suspire por mí.",
      "Mi piscina tiene calefacción volcánica.",
      "El caviar de hoy estaba un poco... económico.",
      "Vendo barcos para comprar barcos más grandes.",
      "Mi mayordomo tiene su propio mayordomo.",
      "El aire que respiro está filtrado por seda.",
      "Me aburrí y compré una isla, la devolví ayer.",
      "Las monedas me dan alergia, prefiero el papel.",
      "Mi tarjeta es de vibranio, la tuya de plástico.",
      "Vuelo en primera clase hasta para ir al baño.",
      "Si preguntas el precio, no puedes pagarlo.",
    ];
    return quotes[name.length % quotes.length];
  }
}

enum _CardTier { standard, gold, platinum, black }

class _CardStyles {
  final LinearGradient gradient;
  final Color accent;
  final String tierName;
  _CardStyles({required this.gradient, required this.accent, required this.tierName});
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
            Text(value, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _VisaBackgroundPattern extends CustomPainter {
  final Color color;
  _VisaBackgroundPattern({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    for (double i = -size.height; i < size.width; i += 30) {
      path.moveTo(i, 0);
      path.lineTo(i + size.height * 1.5, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
