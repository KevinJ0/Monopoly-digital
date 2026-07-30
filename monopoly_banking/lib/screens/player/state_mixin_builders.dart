part of '../player_screen.dart';

mixin _PlayerBuilders on State<PlayerScreen> {
  _PlayerScreenState get _self => this as _PlayerScreenState;

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final session = context.watch<SessionProvider>();
    final stats = context.watch<StatsProvider>();
    final history = wallet.history;

    if (session.role.isNotEmpty && !_self._isExiting) {
      _self._lastColor = session.color;
      _self._lastName = session.name;
      _self._lastAvatarId = session.avatarId;
      _self._lastBalance = wallet.rawBalance.value;
    }

    final displayColor = _self._lastColor ?? kGreen;
    final displayName = _self._lastName ?? '';
    final displayAvatar = _self._lastAvatarId ?? '';
    final displayBalance = _self._lastBalance ?? 0.0;
    final wsConnected = P2PService().wsTransport.clientConnectedNotifier.value || _self._inReconnectionGrace;
    final hasExplicitConnection = _self._wsBankIp != null;
    final playerReady = session.isHandshakeDone && wsConnected && hasExplicitConnection;
    final shownBalance = session.isHandshakeDone ? displayBalance : 0.0;
    final shownTier = playerReady ? wallet.currentTier : CardTier.standard;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth > 700;

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
        extendBodyBehindAppBar: true,
        body: MoneyManagerBackground(
          child: PlayerColorBackdrop(
            color: displayColor,
            child: AnimatedSwitcher(
              key: const ValueKey('bodySwitcher'),
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: !playerReady
                  ? _buildWsConnectScreen(displayColor)
                  : isDesktop
                      ? _buildDesktopGameView(
                          wallet: wallet,
                          session: session,
                          stats: stats,
                          history: history,
                          displayColor: displayColor,
                          displayName: displayName,
                          displayAvatar: displayAvatar,
                          displayBalance: shownBalance,
                          shownTier: shownTier,
                        )
                      : _buildGameView(
                          wallet: wallet,
                          session: session,
                          stats: stats,
                          history: history,
                          displayColor: displayColor,
                          displayName: displayName,
                          displayAvatar: displayAvatar,
                          displayBalance: shownBalance,
                          shownTier: shownTier,
                          playerReady: playerReady,
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWsConnectScreen(Color color) {
    return ValueListenableBuilder<bool>(
      valueListenable: P2PService().wsTransport.clientConnectedNotifier,
      builder: (context, connected, _) {
        return ValueListenableBuilder<String>(
          valueListenable: P2PService().wsTransport.connectionStatusNotifier,
          builder: (context, status, _) {
            final connecting = _self._wsConnecting || (!connected && (status.startsWith('Conectando') || status.startsWith('Preparando')));
            return WsConnectButton(
              key: const ValueKey('wsConnect'),
              color: color,
              scanning: _self._wsScanning && !connecting,
              clientConnected: connected,
              connecting: connecting,
              onStartWsClient: _self._startWsClient,
              onStopWsClient: _self._stopWsClient,
              onConnectToBank: (host, port) => _self._connectToWsBank(host, port),
              onBackButtonPressed: () {
                SoundService.playClick();
                _self._confirmGoHome(context.read<SessionProvider>());
              },
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
    required double displayBalance,
    required CardTier shownTier,
    required bool playerReady,
  }) {
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
      key: const ValueKey('playerGameView'),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: CustomScrollView(
              slivers: [
                _buildHeader(displayAvatar, displayColor, displayName, displayBalance, shownTier),
                if (playerReady)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 100),
                      child: BalanceCardSection(
                        balance: displayBalance,
                        color: displayColor,
                        name: displayName,
                        colorId: int.tryParse(session.colorId) ?? 0,
                        history: _self._lastHistory,
                        isBank: false,
                        tier: shownTier,
                      ),
                    ),
                  ),
                if (playerReady)
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
                if (playerReady)
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
                              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: displayColor,
                              foregroundColor: displayColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                                const Text('HISTORIAL',
                                    style: TextStyle(color: kTextSecondary, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: kBgCard, borderRadius: BorderRadius.circular(8)),
                                  child: Text('${filteredHistory.length}', style: const TextStyle(color: kTextSecondary, fontSize: 11)),
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
                        children: [
                          Icon(Icons.search_off_rounded, color: Color(0xFF4B5563), size: 48),
                          SizedBox(height: 12),
                          Text('Sin coincidencias', style: TextStyle(color: kTextSecondary)),
                        ],
                      ),
                    ),
                  )
                else if (playerReady && history.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_rounded, color: Color(0xFF4B5563), size: 48),
                          SizedBox(height: 12),
                          Text('Sin transacciones a\u00fan', style: TextStyle(color: kTextSecondary)),
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
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Conexi\u00f3n perdida. Reintentando...',
                        style: TextStyle(color: kGold, fontWeight: FontWeight.w700, fontSize: 13),
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

  Widget _buildDesktopGameView({
    required WalletController wallet,
    required SessionProvider session,
    required StatsProvider stats,
    required List<TransactionModel> history,
    required Color displayColor,
    required String displayName,
    required String displayAvatar,
    required double displayBalance,
    required CardTier shownTier,
  }) {
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
      key: const ValueKey('playerDesktopGameView'),
      children: [
        Column(
          children: [
            _buildDesktopHeader(displayAvatar, displayColor, displayName, displayBalance, shownTier, stats),
            Expanded(
              child: Row(
                children: [
                  _buildDesktopSidebar(displayColor, displayName, displayBalance, shownTier, session),
                  Container(width: 1, color: kBorder),
                  Expanded(
                    child: _buildDesktopMainContent(
                      displayColor,
                      history,
                      filteredHistory,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        if (_self._inReconnectionGrace)
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
                child: const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Conexi\u00f3n perdida. Reintentando...',
                        style: TextStyle(color: kGold, fontWeight: FontWeight.w700, fontSize: 13),
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

  Widget _buildDesktopHeader(String avatarId, Color color, String name, double balance, CardTier tier, StatsProvider stats) {
    final title = name.isNotEmpty ? name : 'Mi Billetera';
    final tierLabel = _tierName(tier);

    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 8, 20, 10),
      decoration: BoxDecoration(
        color: kBgDark.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          AnimatedAvatar(emoji: avatarId, size: 36, glowColor: color, showIdle: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('JUGADOR', style: TextStyle(color: color, fontSize: 8, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
                    ),
                    if (tier != CardTier.standard) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [kGold.withValues(alpha: 0.3), kGold.withValues(alpha: 0.1)]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tierLabel, style: const TextStyle(color: kGold, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    if (_self._wsBankIp != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.sensors_rounded, size: 12, color: kGreen),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${_self._wsBankIp}:${_self._wsBankPort}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kTextSecondary, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _desktopAppBarStat(Icons.payments_rounded, _compact(stats.totalVolume), color),
          _desktopAppBarDivider(color),
          _desktopAppBarStat(Icons.history_rounded, '${stats.txCount}', color),
          _desktopAppBarDivider(color),
          _desktopAppBarStat(Icons.flag_rounded, 'x${stats.passGoCount}', color),
          const SizedBox(width: 12),
          Container(width: 1, height: 28, color: kBorder),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: kRed, size: 18),
            tooltip: 'Cerrar Sesi\u00f3n',
            onPressed: () {
              SoundService.playClick();
              _self._confirmExit(context.read<SessionProvider>());
            },
          ),
        ],
      ),
    );
  }

  Widget _desktopAppBarStat(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _desktopAppBarDivider(Color color) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: color.withValues(alpha: 0.15),
    );
  }

  Widget _buildDesktopSidebar(Color displayColor, String displayName, double displayBalance, CardTier tier, SessionProvider session) {
    return SizedBox(
      width: 400,
      child: Container(
        color: kBgDark.withValues(alpha: 0.1),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BalanceCardSection(
                      balance: displayBalance,
                      color: displayColor,
                      name: displayName,
                      colorId: int.tryParse(session.colorId) ?? 0,
                      history: _self._lastHistory,
                      isBank: false,
                      tier: tier,
                    ),
                    const SizedBox(height: 16),
                    VaultSectionWidget(
                      color: displayColor,
                      onInvest: _self._showInvestDialog,
                      onWithdraw: _self._showWithdrawDialog,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () => _self._showPlayerTransferDialog(
                            context.read<WalletController>(),
                            displayColor,
                          ),
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: const Text(
                            'Transferir a jugador',
                            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: displayColor,
                            foregroundColor: displayColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: TransportSelector(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopMainContent(Color displayColor, List<TransactionModel> history, List<TransactionModel> filteredHistory) {
    return Column(
      children: [
        if (history.isNotEmpty || filteredHistory.isNotEmpty)
          Expanded(
            child: _buildDesktopHistorySection(displayColor, filteredHistory, history),
          ),
        if (history.isEmpty && filteredHistory.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_rounded, color: Color(0xFF2A3241), size: 64),
                  SizedBox(height: 16),
                  Text('Sin transacciones a\u00fan', style: TextStyle(color: kTextSecondary, fontSize: 15)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopHistorySection(Color displayColor, List<TransactionModel> filteredHistory, List<TransactionModel> history) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: kBgCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: kGold, size: 18),
                const SizedBox(width: 10),
                const Text(
                  'HISTORIAL',
                  style: TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(8)),
                  child: Text('${filteredHistory.length}', style: const TextStyle(color: kTextSecondary, fontSize: 11)),
                ),
              ],
            ),
          ),
          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: _buildDesktopFilterControls(history),
            ),
          if (filteredHistory.isEmpty && history.isNotEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, color: Color(0xFF4B5563), size: 40),
                    SizedBox(height: 8),
                    Text('Sin coincidencias', style: TextStyle(color: kTextSecondary)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: filteredHistory.length,
                itemBuilder: (_, i) => TransactionTile(tx: filteredHistory[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopFilterControls(List<TransactionModel> history) {
    final typeValues = history.map((tx) => tx.type).where((t) => t.isNotEmpty).toSet().toList()..sort();
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _self._walletFilterType,
                isDense: true,
                hint: const Text('Todos', style: TextStyle(color: kTextSecondary, fontSize: 11)),
                dropdownColor: kBgCard,
                style: const TextStyle(color: kTextPrimary, fontSize: 11),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 11))),
                  ...typeValues.map((t) => DropdownMenuItem(value: t, child: Text(_walletTypeLabel(t), style: const TextStyle(fontSize: 11)))),
                ],
                onChanged: (v) => setState(() => _self._walletFilterType = v),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _self._walletSortBy,
                isDense: true,
                dropdownColor: kBgCard,
                style: const TextStyle(color: kTextPrimary, fontSize: 11),
                items: const [
                  DropdownMenuItem(value: 'date', child: Text('Fecha', style: TextStyle(fontSize: 11))),
                  DropdownMenuItem(value: 'amount', child: Text('Monto', style: TextStyle(fontSize: 11))),
                ],
                onChanged: (v) => setState(() => _self._walletSortBy = v!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => _self._walletSortAscending = !_self._walletSortAscending),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: Icon(
              _self._walletSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: kTextSecondary,
              size: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String avatarId, Color color, String name, double balance, CardTier tier) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;
    final title = name.isNotEmpty ? name : 'Mi Billetera';
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
                border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 6 : 12, 12),
                    child: Row(
                      children: [
                        AnimatedAvatar(emoji: avatarId, size: compact ? 36 : 42, glowColor: color, showIdle: true),
                        SizedBox(width: compact ? 10 : 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: kTextPrimary, fontSize: compact ? 15 : 17, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      'JUGADOR',
                                      style: TextStyle(color: color, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (tier != CardTier.standard)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: [kGold.withValues(alpha: 0.3), kGold.withValues(alpha: 0.1)]),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(tierLabel,
                                            style: const TextStyle(color: kGold, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w800)),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout_rounded, color: kRed, size: 20),
                          tooltip: 'Cerrar Sesi\u00f3n',
                          onPressed: () => _self._confirmExit(context.read<SessionProvider>()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_self._wsBankIp != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Row(
                        children: [
                          Icon(Icons.sensors_rounded, size: 14, color: kGreen),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Conectado a ${_self._wsBankIp}:${_self._wsBankPort}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kTextSecondary, fontSize: 11),
                            ),
                          ),
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
              border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
            ),
            child: Row(
              children: [
                Expanded(child: StatChip(label: 'Volumen', value: _compact(stats.totalVolume), icon: Icons.payments_rounded, color: color)),
                Container(width: 1, height: 28, color: color.withValues(alpha: 0.1)),
                Expanded(child: StatChip(label: 'Tx', value: stats.txCount.toString(), icon: Icons.history_rounded, color: color)),
                Container(width: 1, height: 28, color: color.withValues(alpha: 0.1)),
                Expanded(child: StatChip(label: 'Pass GO', value: 'x${stats.passGoCount}', icon: Icons.flag_rounded, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
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
            decoration: BoxDecoration(color: kBgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _self._walletFilterType,
                hint: const Text('Todos los tipos', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                dropdownColor: kBgCard,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos los tipos', style: TextStyle(color: kTextPrimary, fontSize: 12))),
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
            decoration: BoxDecoration(color: kBgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _self._walletSortBy,
                dropdownColor: kBgCard,
                items: const [
                  DropdownMenuItem(value: 'date', child: Text('Ordenar por fecha', style: TextStyle(color: kTextPrimary, fontSize: 12))),
                  DropdownMenuItem(value: 'amount', child: Text('Ordenar por monto', style: TextStyle(color: kTextPrimary, fontSize: 12))),
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
            decoration: BoxDecoration(color: kBgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
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
    if (type.startsWith('custom_')) {
      final customId = type.substring('custom_'.length);
      final match = BankSettingsService().customOps.where((c) => c.id == customId).firstOrNull;
      return match?.name ?? 'Operación personalizada';
    }
    return switch (type) {
      'passGo' || 'bank_pass_go_sent' => 'Pasar por GO',
      'received' || 'bank_payment_sent' => 'Recibido',
      'payment' || 'bank_charge_received' => 'Cobro',
      'charge' || 'sync_debit' || 'bank_sync_debit' => 'Cargado',
      'transfer_received' || 'bank_transfer_received' || 'bank_transfer_delivered' => 'Transferencia recibida',
      'transfer_held' || 'bank_transfer_held' => 'Retenido',
      'transfer_cancelled' || 'bank_transfer_cancelled' => 'Devuelto',
      'handshake_initial' || 'bank_player_joined' => 'Vinculación',
      'handshake_reconnect' || 'handshake_restore' || 'bank_player_reconnected' => 'Reconexión',
      'investment_opened' || 'bank_investment_opened' => 'Inversión iniciada',
      'investment_completed' || 'bank_investment_completed' => 'Inversión completada',
      'investment_early_withdrawal' || 'bank_investment_early_withdrawal' => 'Retiro de inversión',
      'bankruptcy' || 'bank_bankruptcy' => 'Bancarrota',
      'sync_credit' || 'bank_sync_credit' => 'Sincronización',
      _ => type,
    };
  }
}
