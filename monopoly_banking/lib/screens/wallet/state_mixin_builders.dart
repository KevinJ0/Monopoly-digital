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
      _self._lastColorId = int.tryParse(session.colorId) ?? 0;
      _self._lastBalance = wallet.rawBalance.value;
    }

    final displayColor = _self._lastColor ?? kGreen;
    final displayName = _self._lastName ?? '';
    final displayAvatar = _self._lastAvatarId ?? '';
    final displayRole = _self._lastRole ?? 'cliente';
    final displayColorId = _self._lastColorId ?? 0;
    final displayBalance = _self._lastBalance ?? 0.0;
    final isBank = displayRole == 'banco';
    final wsConnected = isBank || P2PService().wsTransport.clientConnectedNotifier.value || _self._inReconnectionGrace;
    final hasExplicitConnection = isBank || _self._wsBankIp != null;
    final playerReady = isBank || (session.isHandshakeDone && wsConnected && hasExplicitConnection);
    final shownBalance = isBank || session.isHandshakeDone ? displayBalance : 0.0;
    final shownTier = playerReady ? wallet.currentTier : CardTier.standard;
    debugPrint(
        '[┊] BUILD isBank=$isBank wsConnected=$wsConnected playerReady=$playerReady role=$displayRole handshakeDone=${session.isHandshakeDone} myName=$displayName lastBalance=$displayBalance shownBalance=$shownBalance rawBalance=${wallet.rawBalance.value}');
    debugPrint('[┊] ROUTER_CHECK hasSession=${session.role.isNotEmpty && session.avatarId.isNotEmpty} isBank=${session.isBank}');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (playerReady) {
          _self._confirmExit(session);
        } else {
          _self._confirmGoHome(session);
        }
      },
      child: Scaffold(
        backgroundColor: kBgDark,
        body: SafeArea(
          child: IndexedStack(
            index: playerReady ? 1 : 0,
            children: [
              _buildWsConnectScreen(displayColor),
              MonopolyBackground(
                child: PlayerColorBackdrop(
                  color: displayColor,
                  child: _buildGameView(
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
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWsConnectScreen(Color color) {
    return MonopolyBackground(
      child: PlayerColorBackdrop(
        color: color,
        child: ValueListenableBuilder<bool>(
          valueListenable: P2PService().wsTransport.clientConnectedNotifier,
          builder: (context, connected, _) {
            return ValueListenableBuilder<String>(
              valueListenable: P2PService().wsTransport.connectionStatusNotifier,
              builder: (context, status, _) {
                final connecting = _self._wsConnecting || (!connected && (status.startsWith('Conectando') || status.startsWith('Preparando')));
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    WsConnectButton(
                      key: const ValueKey('wsConnect'),
                      color: color,
                      scanning: _self._wsScanning && !connecting,
                      clientConnected: connected,
                      connecting: connecting,
                      onStartWsClient: _self._startWsClient,
                      onStopWsClient: _self._stopWsClient,
                      onConnectToBank: (host, port) => _self._connectToBank(host, port: port),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
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
  }) {
    debugPrint('[┊] GAME_VIEW BUILDING displayName=$displayName playerReady=$playerReady isBank=$isBank history=${history.length}');

    final filteredHistory = (() {
      var result = _self._walletFilterType != null ? history.where((tx) => tx.type == _self._walletFilterType).toList() : history.toList();
      result.sort((a, b) {
        int cmp;
        if (_self._walletSortBy == 'amount') {
          cmp = a.amount.compareTo(b.amount);
        } else {
          cmp = a.timestamp.compareTo(b.timestamp);
        }
        return _self._walletSortAscending ? cmp : -cmp;
      });
      return result;
    })();

    return Stack(
      key: const ValueKey('gameView'),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: CustomScrollView(
              slivers: [
                _buildHeader(displayAvatar, displayColor, displayName, displayRole, isBank, shownBalance, shownTier),
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
                if (isBank)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 350),
                      child: WsBankPanel(
                        onReiniciarWs: () => _self._reiniciarWsServer(),
                        onStopWs: () => _self._detenerWsServer(),
                        onEnsureWsReady: _self._ensureWsReady,
                      ),
                    ),
                  ),
                if (isBank)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 450),
                      child: ConnectedPlayersPanel(
                        color: displayColor,
                        onPlayerTap: _self._showPlayerInfoDialog,
                      ),
                    ),
                  ),
                if (!isBank && playerReady)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 450),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => _self._showPlayerTransferDialog(
                              context.read<WalletController>(),
                              displayColor,
                            ),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text(
                              'Transferir a jugador',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: displayColor,
                              foregroundColor: displayColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
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
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                    '${filteredHistory.length}',
                                    style: const TextStyle(color: kTextSecondary, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            if (history.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildWalletHistoryControls(history),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (playerReady && filteredHistory.isEmpty && history.isNotEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, color: Color(0xFF4B5563), size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Sin coincidencias',
                            style: TextStyle(color: kTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (playerReady && history.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded, color: Color(0xFF4B5563), size: 48),
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
                      (_, i) => TransactionTile(tx: filteredHistory[i]),
                      childCount: filteredHistory.length,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 80 + MediaQuery.of(context).padding.bottom),
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
        if (_self._showWelcome) _buildWelcomeOverlay(displayAvatar, displayColor, displayName),
        if (_self._inReconnectionGrace && playerReady)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kGold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kGold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Conexión perdida. Reintentando...',
                        style: TextStyle(
                          color: kGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
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
                onPressed: () {
                  SoundService.playClick();
                  try {
                    JugadorClient().confirmAction(userName);
                  } catch (e, s) {
                    if (context.mounted) _self._safeShowFriendlyError(e, s);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black),
                child: const Text('CONFIRMAR ACCIÓN FÍSICA', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
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
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 64),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String avatarId, Color color, String name, String role, bool isBank, double balance, CardTier tier) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;
    final title = isBank ? 'Banca Central' : (name.isNotEmpty ? name : 'Mi Billetera');
    final subtitle = role.toLowerCase() == 'cliente' ? 'JUGADOR' : role.toUpperCase();
    final tierLabel = _tierName(tier);

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 12, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: kBgDark.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 6 : 12, 12),
                    child: Row(
                      children: [
                        AnimatedAvatar(
                          emoji: avatarId,
                          size: compact ? 36 : 42,
                          glowColor: color,
                          showIdle: true,
                        ),
                        SizedBox(width: compact ? 10 : 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: kTextPrimary,
                                  fontSize: compact ? 15 : 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      subtitle,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 9,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (!isBank && tier != CardTier.standard)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              kGold.withValues(alpha: 0.3),
                                              kGold.withValues(alpha: 0.1),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          tierLabel,
                                          style: const TextStyle(
                                            color: kGold,
                                            fontSize: 9,
                                            letterSpacing: 1,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout_rounded, color: kRed, size: 20),
                          tooltip: 'Cerrar Sesión',
                          onPressed: () {
                            SoundService.playClick();
                            _self._confirmExit(context.read<SessionProvider>());
                          },
                        ),
                        if (compact) const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  if (!isBank) ...[
                    const SizedBox(height: 14),
                    if (_self._wsBankIp != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          children: [
                            Icon(Icons.sensors_rounded, size: 14, color: kGreen),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Conectado a ${_self._wsBankIp}:${_self._wsBankPort}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: kTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (context.read<SessionProvider>().bankDeviceId.isNotEmpty) ...[
                              SizedBox(width: 6),
                              Text(
                                '· ${context.read<SessionProvider>().bankDeviceId.substring(0, 8).toUpperCase()}',
                                style: TextStyle(
                                  color: kTextSecondary.withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _tierName(CardTier tier) {
    switch (tier) {
      case CardTier.gold:
        return 'GOLD';
      case CardTier.platinum:
        return 'PLATINUM';
      case CardTier.black:
        return 'BLACK';
      default:
        return '';
    }
  }

  Widget _buildStatsRow(StatsProvider stats, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kBgDark.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                    child: _StatChip(
                  label: 'Volumen',
                  value: _compact(stats.totalVolume),
                  icon: Icons.payments_rounded,
                  color: color,
                )),
                Container(
                  width: 1,
                  height: 28,
                  color: color.withValues(alpha: 0.1),
                ),
                Expanded(
                    child: _StatChip(
                  label: 'Tx',
                  value: stats.txCount.toString(),
                  icon: Icons.history_rounded,
                  color: color,
                )),
                Container(
                  width: 1,
                  height: 28,
                  color: color.withValues(alpha: 0.1),
                ),
                Expanded(
                    child: _StatChip(
                  label: 'Pass GO',
                  value: 'x${stats.passGoCount}',
                  icon: Icons.flag_rounded,
                  color: color,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _triggerWelcomeAnimation(String? name) async {
    _self._showWelcome = true;
    if (mounted) setState(() {});
    _self._welcomeCtrl.forward(from: 0);
  }

  Future<void> _hideWelcome() async {
    await _self._welcomeCtrl.reverse();
    if (mounted) setState(() => _self._showWelcome = false);
  }

  String _compact(double val) {
    return formatMoney(val);
  }

  Widget _buildWalletHistoryControls(List<TransactionModel> history) {
    final typeValues = history.map((tx) => tx.type).where((t) => t.isNotEmpty).toSet().toList()..sort();
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _self._walletFilterType,
                hint: const Text('Todos los tipos', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                dropdownColor: kBgCard,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Todos los tipos', style: TextStyle(color: kTextPrimary, fontSize: 12)),
                  ),
                  ...typeValues.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_walletTypeLabel(t), style: const TextStyle(color: kTextPrimary, fontSize: 12)),
                      )),
                ],
                onChanged: (v) => setState(() => _self._walletFilterType = v),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _self._walletSortBy,
                dropdownColor: kBgCard,
                items: const [
                  DropdownMenuItem(
                    value: 'date',
                    child: Text('Ordenar por fecha', style: TextStyle(color: kTextPrimary, fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: 'amount',
                    child: Text('Ordenar por monto', style: TextStyle(color: kTextPrimary, fontSize: 12)),
                  ),
                ],
                onChanged: (v) => setState(() => _self._walletSortBy = v!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _self._walletSortAscending = !_self._walletSortAscending),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: Icon(
              _self._walletSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: kTextSecondary,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  String _walletTypeLabel(String type) {
    return switch (type) {
      'passGo' || 'bank_pass_go_sent' => 'Pasar por GO',
      'received' || 'bank_payment_sent' => 'Recibido',
      'payment' || 'bank_charge_received' => 'Cobro',
      'charge' || 'sync_debit' => 'Cargado',
      'transfer_received' || 'bank_transfer_received' => 'Transferencia recibida',
      'transfer_held' || 'bank_transfer_held' => 'Retenido',
      'transfer_cancelled' || 'bank_transfer_cancelled' => 'Devuelto',
      'handshake_initial' || 'bank_player_joined' => 'Vinculaci\u00f3n',
      'handshake_reconnect' || 'bank_player_reconnected' => 'Reconexi\u00f3n',
      'investment_opened' => 'Inversi\u00f3n',
      'investment_completed' => 'Inversi\u00f3n completada',
      'bankruptcy' || 'bank_bankruptcy' => 'Bancarrota',
      'sync_credit' => 'Sincronizaci\u00f3n',
      _ => type,
    };
  }
}
