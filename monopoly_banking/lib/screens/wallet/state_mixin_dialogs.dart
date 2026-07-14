part of '../wallet_screen.dart';

mixin _WalletDialogs on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;
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

  Future<void> _safeShowFriendlyError(dynamic error,
      [StackTrace? stack]) async {
    final friendly = await ErrorTranslatorService().translate(error, stack);
    if (!mounted) return;
    if (friendly.severity == ErrorSeverity.error ||
        friendly.severity == ErrorSeverity.critical) {
      NotificationService().show(
        friendly.message,
        backgroundColor: kRed,
        duration: const Duration(seconds: 5),
      );
    } else {
      NotificationService().show(
        friendly.message,
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> _showPlayerTransferDialog(
    WalletController wallet,
    Color brandColor,
  ) async {
    final amountCtrl = TextEditingController();
    final session = context.read<SessionProvider>();
    var sending = false;
    var message = '';

    _self._dialogActive = true;
    final completer = Completer<void>();
    _self._pendingTransferCompleter = completer;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            if (sending) {
              return AlertDialog(
                backgroundColor: kBgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: SizedBox(
                  width: 240,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppSpinner(),
                      const SizedBox(height: 20),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondary),
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: kBgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Transferir a jugador',
                style:
                    TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'El banco retendrá este dinero hasta que el jugador receptor acerque su celular.',
                    style: TextStyle(color: kTextSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      prefixText: '\$ ',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    SoundService.playClick();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandColor,
                    foregroundColor: brandColor.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                  ),
                  onPressed: () async {
                    SoundService.playClick();
                    final amount = double.tryParse(amountCtrl.text) ?? 0;
                    if (amount <= 0) {
                      _showToast('Ingresa un monto válido.', kRed);
                      return;
                    }
                    final transportType = P2PService().currentType;
                    final transport = P2PService().bleTransport;
                    if (transportType == TransportType.ble &&
                        !transport.clientConnectedNotifier.value) {
                      _showToast('Conéctate al banco por BLE primero.', kRed);
                      return;
                    }

                    setDialogState(() {
                      sending = true;
                      message = 'Verificando proximidad con el banco...';
                    });

                    var contactReady = false;
                    final timeout = DateTime.now().add(const Duration(seconds: 15));
                    while (!contactReady && DateTime.now().isBefore(timeout)) {
                      final rssi = await transport.readCurrentRssi();
                      if (rssi != null && transport.isRssiContactReady(rssi)) {
                        contactReady = true;
                        break;
                      }
                      await Future<void>.delayed(const Duration(seconds: 2));
                    }
                    if (!contactReady) {
                      if (mounted) {
                        setDialogState(() {
                          sending = false;
                          message = '';
                        });
                        _showToast(
                          'No se detectó proximidad con el banco. Acerca los dispositivos.',
                          Colors.orange,
                        );
                      }
                      return;
                    }

                    setDialogState(() {
                      message = 'Esperando confirmación del banco...';
                    });

                    try {
                      final requestId =
                          'transfer-${session.name}-${DateTime.now().microsecondsSinceEpoch}';
                      final request = {
                        'type': 'transfer_hold_request',
                        'requestId': requestId,
                        'amount': amount,
                        'fromPlayerId': session.name,
                        'fromName': session.name,
                        'deviceInstallationId':
                            DeviceIdentityService.installationId,
                      };
                      P2PService().setTransport(TransportType.ble);
                      await P2PService().sendPayload(request);

                      final pendingCompleter = _self._pendingTransferCompleter;
                      if (pendingCompleter != null) {
                        await pendingCompleter.future
                            .timeout(const Duration(seconds: 12));
                      }
                    } on TimeoutException {
                      if (mounted) {
                        _showToast('El banco no confirmó a tiempo.', kRed);
                      }
                    } catch (e, s) {
                      if (mounted) _safeShowFriendlyError(e, s);
                    }
                    if (mounted && dialogContext.mounted) {
                      Navigator.pop(dialogContext);
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
      _self._pendingTransferCompleter = null;
      amountCtrl.dispose();
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
                        CurvedAnimation(
                            parent: anim1, curve: Curves.elasticOut)),
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
                      _self._confettiCtrl.play();
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
    } finally {
      _self._evolutionDialogOpen = false;
    }
  }

  void _openBankruptcyScreen() {
    if (_self._bankruptcyScreenOpen || !mounted) return;
    final session = context.read<SessionProvider>();
    if (session.isBank) return;
    _self._bankruptcyScreenOpen = true;
    unawaited(
      Navigator.of(context)
          .push<void>(
            GameFadeRoute(
              page: BankruptcyScreen(playerName: session.name),
            ),
          )
          .whenComplete(() => _self._bankruptcyScreenOpen = false),
    );
  }

  Future<void> _openBleDebug() async {
    SoundService.playClick();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BleTestScreen()),
    );
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
              setState(() => _self._isExiting = true);
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

  void _showInvestDialog(WalletController wallet, Color brandColor) {
    final amountCtrl = TextEditingController();
    int selectedPasses = 3;
    bool submitting = false;

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
        final wouldEmptyBalance = val > 0 && (wallet.balance - val) <= 0;

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
                const Text(
                    'Acerca tu dispositivo al banco para enviar la solicitud de inversión.',
                    style: TextStyle(color: kGold, fontSize: 12, height: 1.35)),
                const SizedBox(height: 16),
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
                if (wouldEmptyBalance) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No puedes invertir todo tu saldo. Debe quedar al menos \$1 en tu cuenta.',
                    style: TextStyle(color: kRed, fontSize: 11, height: 1.3),
                  ),
                ],
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
                onPressed: submitting
                    ? null
                    : () {
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
              onPressed: (submitting || wouldEmptyBalance)
                  ? null
                  : () async {
                      SoundService.playClick();
                      final finalVal = double.tryParse(
                              amountCtrl.text.replaceAll(',', '')) ??
                          0;
                      if (finalVal > 0) {
                        setStateSB(() => submitting = true);
                        try {
                          await _self._requestBankOperation({
                            'operation': 'invest',
                            'amount': finalVal,
                            'passes': selectedPasses,
                          });
                          if (context.mounted) Navigator.pop(context);
                        } catch (e, s) {
                          if (context.mounted) _safeShowFriendlyError(e, s);
                        } finally {
                          if (context.mounted) {
                            setStateSB(() => submitting = false);
                          }
                        }
                      }
                    },
              child: submitting
                  ? const AppSpinner(
                      size: 20,
                      color: Colors.white,
                    )
                  : const Text('Invertir'),
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
          title: Text('Retiro de Inversión',
              style: TextStyle(color: brandColor, fontWeight: FontWeight.bold)),
          content: const Text(
            '¡Enhorabuena! Has cumplido el plazo de tu inversión. Se acreditará tu capital más los intereses generados a tu cuenta principal.',
            style: TextStyle(color: Colors.white70),
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
                  backgroundColor: brandColor, foregroundColor: Colors.white),
              onPressed: () async {
                SoundService.playClick();
                try {
                  await _self._requestBankOperation({
                    'operation': 'withdraw_investment',
                  });
                  if (mounted) Navigator.pop(context);
                } catch (e, s) {
                  if (mounted) _safeShowFriendlyError(e, s);
                }
              },
              child: const Text('Liquidar Inversión'),
            ),
          ],
        ));
  }

  void _showPlayerInfoDialog(BleConnectedPlayer player) {
    final ledger = BankLedgerService();
    final account = ledger.accountFor(player.displayName);
    final transactions = ledger.transactionHistory
        .where((tx) => tx['playerId'] == player.displayName)
        .toList();
    final volume = transactions.fold<double>(
      0,
      (sum, tx) => sum + (((tx['amount'] as num?)?.toDouble() ?? 0).abs()),
    );
    final passGoCount =
        transactions.where((tx) => tx['type'] == 'passGo').length;
    final txCount = transactions.length;
    final balance = account?.balance ?? 0;
    final playerColor = _playerColor(player.colorId);
    final avatar = player.avatarId.isNotEmpty
        ? player.avatarId
        : '\u{1F464}';
    final tier = _playerTier(balance);
    final tierLabel = _tierLabel(tier);
    final tierColor = _tierColor(tier);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: DefaultTabController(
          length: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: playerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            avatar,
                            style: TextStyle(
                              fontSize: 20,
                              color: playerColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    labelColor: kGold,
                    unselectedLabelColor: kTextSecondary,
                    indicatorColor: kGold,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    tabs: const [
                      Tab(text: 'Datos Jugador'),
                      Tab(text: 'Datos Conexion'),
                    ],
                  ),
                  Flexible(
                    child: TabBarView(
                      children: [
                        PlayerInfoView(
                          player: player,
                          balance: balance,
                          volume: volume,
                          passGoCount: passGoCount,
                          txCount: txCount,
                          tier: tier,
                          tierLabel: tierLabel,
                          tierColor: tierColor,
                          transactions: transactions,
                        ),
                        _buildConnectionInfoTab(player),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _playerTier(double balance) {
    if (balance >= 15000) return 'black';
    if (balance >= 8000) return 'platinum';
    if (balance >= 4000) return 'gold';
    return 'standard';
  }

  String _tierLabel(String tier) {
    return switch (tier) {
      'black' => 'ULTIMATE BLACK',
      'platinum' => 'PLATINUM PRESTIGE',
      'gold' => 'GOLD MEMBERSHIP',
      _ => 'CLASSIC EDITION',
    };
  }

  Color _tierColor(String tier) {
    return switch (tier) {
      'standard' => const Color(0xFF90A4AE),
      'gold' => const Color(0xFFFFD700),
      'platinum' => const Color(0xFF1E88E5),
      'black' => const Color(0xFF424242),
      _ => const Color(0xFF90A4AE),
    };
  }

  Color _playerColor(String colorId) {
    const colors = [
      Color(0xFFE53935),
      Color(0xFF8E24AA),
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFFDD835),
      Color(0xFFFF7043),
      Color(0xFF00ACC1),
      Color(0xFFECEFF1),
    ];
    final index = int.tryParse(colorId) ?? 0;
    if (index >= 0 && index < colors.length) return colors[index];
    return colors[0];
  }

  Widget _buildConnectionInfoTab(BleConnectedPlayer player) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Dispositivo'),
          _detailRow('Nombre',
              player.name.isNotEmpty ? player.name : '-'),
          _detailRow(
              'Dispositivo', player.displayDeviceName),
          _detailRow('ID BLE', player.id),
          _detailRow(
              'ID Instalaci\u00f3n',
              player.deviceInstallationId.isNotEmpty
                  ? player.deviceInstallationId
                  : '-'),
          const SizedBox(height: 12),
          _buildSectionHeader('Estado Conexi\u00f3n'),
          _detailRow('Handshake',
              player.playing ? 'Completado' : 'Pendiente'),
          _detailRow('Suscripci\u00f3n GATT',
              player.subscribed ? 'Activa' : 'Inactiva'),
          const SizedBox(height: 12),
          _detailRow(
              '\u00daltima actividad',
              _format12h(player.lastSeen)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: kGold,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
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

  String _format12h(DateTime dt) {
    final h = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}






