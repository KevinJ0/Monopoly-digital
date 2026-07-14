part of '../wallet_screen.dart';

mixin _WalletBuilders on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;
  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final session = context.watch<SessionProvider>();
    final stats = context.watch<StatsProvider>();
    final history = wallet.history;

    if (session.role.isNotEmpty && !_self._isExiting) {
      _self._lastRole = session.role;
      _self._lastColor = session.color;
      _self._lastName = session.name;
      _self._lastAvatarId = session.avatarId;
      _self._self._lastColorId = int.tryParse(session.colorId) ?? 0;
      _self._lastBalance = wallet.rawBalance.value;
    }

    final displayColor = _self._lastColor ?? kGreen;
    final displayName = _self._lastName ?? '';
    final displayAvatar = _self._lastAvatarId ?? '';
    final displayRole = _self._lastRole ?? 'cliente';
    final displayColorId = _self._self._lastColorId ?? 0;
    final displayBalance = _self._lastBalance ?? 0.0;
    final isBank = displayRole == 'banco';
    final bleConnected = isBank ||
        P2PService().currentType != TransportType.ble ||
        P2PService().bleTransport.clientConnectedNotifier.value;
    final playerReady = isBank || (session.isHandshakeDone && bleConnected);
    final shownBalance = playerReady ? displayBalance : 0.0;
    // Si el banco no tiene Bluetooth, mostrar pantalla limpia como al inicio
    final bankBleOk = !isBank || P2PService().bleTransport.isEnabled;
    final shownTier = playerReady ? wallet.currentTier : CardTier.standard;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final session = context.read<SessionProvider>();
        _self._confirmExit(session);
      },
      child: Scaffold(
        backgroundColor: kBgDark,
        floatingActionButton: !isBank && playerReady && !_self._showWelcome
                ? FloatingActionButton.extended(
                        heroTag: 'transfer_to_bank_btn',
                        onPressed: () {
                          SoundService.playClick();
                          _self._showPlayerTransferDialog(wallet, displayColor);
                        },
                        backgroundColor: displayColor,
                        foregroundColor: displayColor.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text(
                          'Transferir',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    : const SizedBox.shrink(),
        extendBodyBehindAppBar: true,
        body: MonopolyBackground(
          child: PlayerColorBackdrop(
            color: displayColor,
            child: AnimatedSwitcher(
              key: const ValueKey('bodySwitcher'),
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: !isBank && !playerReady
                  ? _buildBleConnectScreen(displayColor)
                  : _buildGameView(
                      wallet: wallet,
                      session: session,
                      stats: stats,
                      history: history,
                      displayColor: displayColor,
                      displayName: displayName,
                      displayAvatar: displayAvatar,
                      displayRole: displayRole,
                      displayColorId: displayColorId,
                      shownBalance: shownBalance,
                      shownTier: shownTier,
                      playerReady: playerReady,
                      isBank: isBank,
                      bankBleOk: bankBleOk,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBleConnectScreen(Color color) {
    return ValueListenableBuilder<bool>(
      valueListenable: P2PService().bleTransport.clientConnectedNotifier,
      builder: (context, connected, _) {
        return ValueListenableBuilder<String>(
          valueListenable: P2PService().bleTransport.connectionStatusNotifier,
          builder: (context, status, _) {
            final connecting = !connected &&
                (status.startsWith('Conectando') ||
                    status.startsWith('Preparando'));
            return BleConnectButton(
              key: const ValueKey('bleConnect'),
              color: color,
              bleScanning: _self._bleScanning && !connecting,
              clientConnected: connected,
              connecting: connecting,
              onStartBleClient: _self._startBleClient,
              onStopBleClient: _self._stopBleClient,
            );
          },
        );
      },
    );
  }

  Widget _buildGameView({
    required WalletController wallet,
    required SessionProvider session,
    required StatsProvider stats,
    required List<TransactionModel> history,
    required Color displayColor,
    required String displayName,
    required String displayAvatar,
    required String displayRole,
    required int displayColorId,
    required double shownBalance,
    required CardTier shownTier,
    required bool playerReady,
    required bool isBank,
    required bool bankBleOk,
  }) {
    return Stack(
      key: const ValueKey('gameView'),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: CustomScrollView(
              slivers: [
                _buildAppBar(displayAvatar, displayColor, displayName,
                    displayRole, isBank),
                if (!isBank && playerReady)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 100),
                      child: BalanceCardSection(
                        balance: shownBalance,
                        color: displayColor,
                        name: displayName,
                        colorId: displayColorId,
                        history: _self._lastHistory,
                        isBank: isBank,
                        tier: shownTier,
                      ),
                    ),
                  ),
                if (!isBank && playerReady)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 200),
                      child: VaultSectionWidget(
                        color: displayColor,
                        onInvest: _self._showInvestDialog,
                        onWithdraw: _self._showWithdrawDialog,
                      ),
                    ),
                  ),
                if (playerReady)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 300),
                      child: _buildStatsRow(stats, displayColor),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: AnimatedEntry(
                    delay: const Duration(milliseconds: 400),
                    child: isBank
                        ? BleBankPanel(
                            onShowDistanceSettings: () =>
                                _self._showBleDistanceSettings(),
                            onReiniciarBle: () => _self._reiniciarBleBanco(),
                            onStopBle: () => _self._detenerBleBanco(),
                            onEnsureBleReady: _self._ensureBleReady,
                          )
                        : ValueListenableBuilder<TransportType>(
                            valueListenable: P2PService().typeNotifier,
                            builder: (context, type, _) {
                              return ConnectionPanel(
                                color: displayColor,
                                isBank: isBank,
                                bleScanning: _self._bleScanning,
                                onStopBleClient: _self._stopBleClient,
                                onStartBleClient: _self._startBleClient,
                                onConnectToBleBank: _self._connectToBleBank,
                              );
                            },
                          ),
                  ),
                ),
                if (isBank && bankBleOk)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 450),
                      child: ConnectedPlayersPanel(
                        color: displayColor,
                        onPlayerTap: _self._showPlayerInfoDialog,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: TransportSelector(),
                  ),
                ),
                if (playerReady)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 500),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 24, 16, 8),
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
                if (playerReady && history.isEmpty)
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
                else if (playerReady)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => TransactionTile(tx: history[i]),
                      childCount: history.length,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                      height:
                          80 + MediaQuery.of(context).padding.bottom),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _self._confettiCtrl,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [kGold, kGreen, Colors.white, Colors.blue],
            numberOfParticles: 50,
            gravity: 0.1,
          ),
        ),
        if (_self._showWelcome)
          _buildWelcomeOverlay(
              displayAvatar, displayColor, displayName),
      ],
    );
  }

  // ignore: unused_element
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
                    if (context.mounted) _self._safeShowFriendlyError(e, s);
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

  Widget _buildWelcomeOverlay(String avatarId, Color color, String name) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: FadeTransition(
          opacity: _self._welcomeOpacity,
          child: ScaleTransition(
            scale: _self._welcomeScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
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
                  child: AnimatedAvatar(
                    emoji: avatarId,
                    size: 104,
                    glowColor: color,
                    showIdle: true,
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
          AnimatedAvatar(
            emoji: avatarId,
            size: compactActions ? 32 : 36,
            glowColor: color,
            showIdle: false,
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
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bluetooth_rounded, color: kTextSecondary),
              tooltip: 'BLE Debug',
              onPressed: _self._self._openBleDebug,
            ),
        ],
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: kRed),
          tooltip: 'Cerrar Sesión',
          onPressed: () {
            SoundService.playClick();
            _self._confirmExit(context.read<SessionProvider>());
          },
        ),
        if (kDebugMode)
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
              if (value == 'ble') _self._openBleDebug();
            },
            itemBuilder: (context) => [
              if (kDebugMode)
                const PopupMenuItem(
                  value: 'ble',
                  child: Text('BLE Debug'),
                ),
            ],
          ),
      ],
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

  Future<void> _triggerWelcomeAnimation(String? name) async {
    _self._safeSetState(() {
      _self._showWelcome = true;
    });
    await _self._welcomeCtrl.forward();
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      await _self._welcomeCtrl.reverse();
      setState(() => _self._showWelcome = false);
    }
  }

  Future<void> _hideWelcome() async {
    if (_self._showWelcome) {
      await _self._welcomeCtrl.reverse();
      _self._safeSetState(() => _self._showWelcome = false);
    }
  }

  String _compact(double val) {
    return formatMoney(val);
  }
}






