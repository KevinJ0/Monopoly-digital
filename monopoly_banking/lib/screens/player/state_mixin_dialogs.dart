part of '../player_screen.dart';

mixin _PlayerDialogs on State<PlayerScreen> {
  _PlayerScreenState get _self => this as _PlayerScreenState;

  VoidCallback? _bankruptListener;

  void _showToast(String msg, Color color) {
    NotificationService().show(msg, backgroundColor: color);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    if (_self._dialogActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  Future<void> _safeShowFriendlyError(dynamic error, [StackTrace? stack]) async {
    final friendly = await ErrorTranslatorService().translate(error, stack);
    if (!mounted) return;
    if (friendly.severity == ErrorSeverity.error || friendly.severity == ErrorSeverity.critical) {
      NotificationService().show(friendly.message, backgroundColor: kRed, duration: const Duration(seconds: 5));
    } else {
      NotificationService().show(friendly.message, backgroundColor: Colors.orange, duration: const Duration(seconds: 4));
    }
  }

  Future<void> _showPlayerTransferDialog(WalletController wallet, Color brandColor) async {
    final amountCtrl = TextEditingController();
    final session = context.read<SessionProvider>();

    _self._dialogActive = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kBgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Transferir a jugador', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('El banco retendr\u00e1 este dinero hasta que el operador lo entregue al jugador receptor.',
                      style: TextStyle(color: kTextSecondary, height: 1.35)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () { SoundService.playClick(); Navigator.pop(dialogContext); },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandColor,
                    foregroundColor: brandColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                  ),
                  onPressed: () async {
                    SoundService.playClick();
                    final amount = double.tryParse(amountCtrl.text) ?? 0;
                    if (amount <= 0) { _showToast('Ingresa un monto v\u00e1lido.', kRed); return; }
                    if (!P2PService().wsTransport.clientConnectedNotifier.value) {
                      _showToast('Con\u00e9ctate al banco primero.', kRed); return;
                    }
                    Navigator.pop(dialogContext);
                    try {
                      final requestId = 'transfer-${session.name}-${DateTime.now().microsecondsSinceEpoch}';
                      P2PService().setTransport(TransportType.ws);
                      await P2PService().sendPayload({
                        'type': 'transfer_hold_request',
                        'requestId': requestId,
                        'amount': amount,
                        'fromPlayerId': session.name,
                        'fromName': session.name,
                        'deviceInstallationId': DeviceIdentityService.installationId,
                      });
                    } catch (e, s) {
                      if (mounted) _safeShowFriendlyError(e, s);
                    }
                  },
                  child: const Text('Retener en banco'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _self._dialogActive = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!amountCtrl.hasListeners) amountCtrl.dispose();
      });
    }
  }

  void _listenToTierEvolution() {
    final wallet = context.read<WalletController>();
    _self._tierSub?.cancel();
    _self._tierSub = wallet.tierStream.listen((newTier) {
      if (!mounted || _self._evolutionDialogOpen) return;
      final pending = _self._pendingCelebrationTier;
      if (pending == null || newTier.index > pending.index) {
        _self._pendingCelebrationTier = newTier;
      }
      _self._tierCelebrationTimer?.cancel();
      _self._tierCelebrationTimer = Timer(const Duration(milliseconds: 300), () {
        final tier = _self._pendingCelebrationTier;
        _self._pendingCelebrationTier = null;
        if (mounted && tier != null && !_self._evolutionDialogOpen) {
          _showEvolutionAnimation(tier);
        }
      });
    });
  }

  void _showEvolutionAnimation(CardTier tier) async {
    if (_self._evolutionDialogOpen || !mounted) return;
    _self._evolutionDialogOpen = true;
    HapticFeedback.vibrate();
    SoundService.playSuccess();

    String tierName = '';
    Color accentColor = Colors.white;
    switch (tier) {
      case CardTier.gold:
        tierName = 'GOLD';
        accentColor = const Color(0xFFBF953F);
      case CardTier.platinum:
        tierName = 'PLATINUM';
        accentColor = const Color(0xFFE0E0E0);
      case CardTier.black:
        tierName = 'ULTIMATE BLACK';
        accentColor = Colors.blueAccent;
      default:
        tierName = 'STANDARD';
    }

    try {
      await showGeneralDialog<void>(
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
                    child: Text('\u00a1TU TARJETA EST\u00c1 EVOLUCIONANDO!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 4)),
                  ),
                  const SizedBox(height: 40),
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.5, end: 1.2).animate(CurvedAnimation(parent: anim1, curve: Curves.elasticOut)),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.5), blurRadius: 50, spreadRadius: 10)],
                      ),
                      child: Icon(Icons.auto_awesome_rounded, size: 120, color: accentColor),
                    ),
                  ),
                  const SizedBox(height: 40),
                  AnimatedEntry(
                    delay: const Duration(milliseconds: 600),
                    child: Column(
                      children: [
                        const Text('\u00a1FELICIDADES!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)),
                        const SizedBox(height: 8),
                        Text('HAS ALCANZADO EL NIVEL $tierName',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: accentColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                  ElevatedButton(
                    onPressed: () { _self._confettiCtrl.play(); Navigator.pop(ctx); },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('VER MI NUEVA TARJETA', style: TextStyle(fontWeight: FontWeight.bold)),
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
    } finally {
      _self._evolutionDialogOpen = false;
    }
  }

  void _openBankruptcyScreen() {
    if (_self._bankruptcyScreenOpen || !mounted) return;
    final session = context.read<SessionProvider>();
    _self._bankruptcyScreenOpen = true;
    unawaited(
      Navigator.of(context)
          .push<void>(
            GameFadeRoute(page: BankruptcyScreen(playerName: session.name)),
          )
          .whenComplete(() => _self._bankruptcyScreenOpen = false),
    );
  }

  void _confirmExit(SessionProvider session) {
    showPremiumDialog(
      context: context,
      child: AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('\u00bfSalir al inicio?', style: TextStyle(color: kTextPrimary)),
        content: const Text('Volver\u00e1s a la pantalla de selecci\u00f3n de roles.',
            style: TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () { SoundService.playClick(); Navigator.pop(context); },
            child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _self._userRequestedWsDisconnect = true;
              P2PService().wsTransport.stop().then((_) {
                _self._userRequestedWsDisconnect = false;
              });
              session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _self._lastColor ?? Colors.orange,
              foregroundColor: (_self._lastColor ?? Colors.orange).computeLuminance() > 0.5 ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  void _confirmGoHome(SessionProvider session) {
    showPremiumDialog(
      context: context,
      child: AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('\u00bfSalir al inicio?', style: TextStyle(color: kTextPrimary)),
        content: const Text('Volver\u00e1s a la pantalla de selecci\u00f3n de roles.',
            style: TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () { SoundService.playClick(); Navigator.pop(context); },
            child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _self._userRequestedWsDisconnect = true;
              P2PService().wsTransport.stop().then((_) {
                _self._userRequestedWsDisconnect = false;
              });
              session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  void _showInvestDialog(WalletController wallet, Color brandColor) {
    final amountCtrl = TextEditingController();
    int selectedPasses = 3;
    bool submitting = false;

    showPremiumDialog(
      context: context,
      child: StatefulBuilder(builder: (context, setStateSB) {
        final val = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
        double getRate(int passes) {
          return switch (passes) { 1 => 0.05, 2 => 0.07, 3 => 0.10, 4 => 0.12, 5 => 0.15, _ => 0.05 };
        }
        final rate = getRate(selectedPasses);
        final expectedTotal = val > 0 ? val * rate * selectedPasses : 0;
        final wouldEmptyBalance = val > 0 && (wallet.balance - val) <= 0;

        return AlertDialog(
          backgroundColor: kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nueva Inversi\u00f3n', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Acerca tu dispositivo al banco para enviar la solicitud de inversi\u00f3n.',
                    style: TextStyle(color: kGold, fontSize: 12, height: 1.35)),
                const SizedBox(height: 16),
                const Text('Monto a Invertir', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setStateSB(() {}),
                  decoration: const InputDecoration(prefixText: '\$ ', filled: true, fillColor: kBgDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none)),
                ),
                if (wouldEmptyBalance) ...[
                  const SizedBox(height: 8),
                  const Text('No puedes invertir todo tu saldo. Debe quedar al menos \$1 en tu cuenta.',
                      style: TextStyle(color: kRed, fontSize: 11, height: 1.3)),
                ],
                const SizedBox(height: 20),
                const Text('Plazo (Pases por GO)', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (index) {
                    final passes = index + 1;
                    final isSelected = selectedPasses == passes;
                    return GestureDetector(
                      onTap: () { SoundService.playClick(); setStateSB(() => selectedPasses = passes); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? brandColor : kBgDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? brandColor : Colors.white10),
                        ),
                        child: Text('$passes', style: TextStyle(
                            color: isSelected ? (brandColor.computeLuminance() > 0.5 ? Colors.black : Colors.white) : Colors.white54,
                            fontWeight: FontWeight.bold, fontSize: 16)),
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
                      Text('Ganancia Estimada: ${formatMoney(expectedTotal)}',
                          style: const TextStyle(color: kGreenGlow, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () { SoundService.playClick(); Navigator.pop(context); },
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                foregroundColor: brandColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              ),
              onPressed: (submitting || wouldEmptyBalance) ? null : () async {
                SoundService.playClick();
                final finalVal = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                if (finalVal > 0) {
                  setStateSB(() => submitting = true);
                  try {
                    await _self._requestBankOperation({'operation': 'invest', 'amount': finalVal, 'passes': selectedPasses});
                    if (context.mounted) Navigator.pop(context);
                  } catch (e, s) {
                    if (context.mounted) _safeShowFriendlyError(e, s);
                  } finally {
                    if (context.mounted) setStateSB(() => submitting = false);
                  }
                }
              },
              child: submitting ? const AppSpinner(size: 20, color: Colors.white) : const Text('Invertir'),
            ),
          ],
        );
      }),
    );
  }

  void _showWithdrawDialog(WalletController wallet, Color brandColor) {
    showPremiumDialog(
      context: context,
      child: AlertDialog(
        backgroundColor: kBgCard,
        title: Text('Retiro de Inversi\u00f3n', style: TextStyle(color: brandColor, fontWeight: FontWeight.bold)),
        content: const Text(
          '\u00a1Enhorabuena! Has cumplido el plazo de tu inversi\u00f3n. Se acreditar\u00e1 tu capital m\u00e1s los intereses generados a tu cuenta principal.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () { SoundService.playClick(); Navigator.pop(context); },
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white),
            onPressed: () async {
              SoundService.playClick();
              try {
                await _self._requestBankOperation({'operation': 'withdraw_investment'});
                if (mounted) Navigator.pop(context);
              } catch (e, s) {
                if (mounted) _safeShowFriendlyError(e, s);
              }
            },
            child: const Text('Liquidar Inversi\u00f3n'),
          ),
        ],
      ),
    );
  }
}
