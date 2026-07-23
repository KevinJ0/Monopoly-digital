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
      _self._lastColor = session.color;
      _self._lastName = session.name;
      _self._lastAvatarId = session.avatarId;
      _self._lastBalance = wallet.rawBalance.value;
    }

    final displayColor = _self._lastColor ?? kGreen;
    final displayName = _self._lastName ?? '';
    final displayAvatar = _self._lastAvatarId ?? '';
    final displayBalance = _self._lastBalance ?? 0.0;

    debugPrint('[┊] BANK_BUILD displayName=$displayName lastBalance=$displayBalance history=${history.length}');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _self._confirmExit(session);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _buildGameView(
            wallet: wallet,
            session: session,
            stats: stats,
            history: history,
            displayColor: displayColor,
            displayName: displayName,
            displayAvatar: displayAvatar,
            displayBalance: displayBalance,
          ),
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
    required double displayBalance,
  }) {
    debugPrint('[┊] BANK_GAME_VIEW BUILDING displayName=$displayName history=${history.length}');

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
                _buildHeader(displayAvatar, displayColor, displayName, displayBalance),
                SliverToBoxAdapter(
                  child: AnimatedEntry(
                    delay: const Duration(milliseconds: 300),
                    child: WsBankPanel(
                      onReiniciarWs: () => _self._reiniciarWsServer(),
                      onStopWs: () => _self._detenerWsServer(),
                      onEnsureWsReady: _self._ensureWsReady,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntry(
                    delay: const Duration(milliseconds: 450),
                    child: _buildStatsRow(stats, displayColor),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntry(
                    delay: const Duration(milliseconds: 500),
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
                if (history.isNotEmpty)
                  SliverToBoxAdapter(
                    child: AnimatedEntry(
                      delay: const Duration(milliseconds: 550),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
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
                            const SizedBox(height: 10),
                            _buildWalletHistoryControls(history),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (filteredHistory.isEmpty && history.isNotEmpty)
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
                else if (history.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 24),
                          Icon(Icons.receipt_long_rounded, color: Color(0xFF4B5563), size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Sin transacciones a\u00fan',
                            style: TextStyle(color: kTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
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
      ],
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
                  '\u00a1BIENVENIDO!',
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

  Widget _buildHeader(String avatarId, Color color, String name, double balance) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;

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
              child: Padding(
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
                            'Banca Central',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kTextPrimary,
                              fontSize: compact ? 15 : 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'BANCO',
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: kRed, size: 20),
                      tooltip: 'Cerrar Sesi\u00f3n',
                      onPressed: () {
                        SoundService.playClick();
                        _self._confirmExit(context.read<SessionProvider>());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                    child: StatChip(
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
                    child: StatChip(
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
                    child: StatChip(
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
      return match?.name ?? 'Operaci\u00f3n personalizada';
    }
    return switch (type) {
      'passGo' || 'bank_pass_go_sent' => 'Pasar por GO',
      'received' || 'bank_payment_sent' => 'Recibido',
      'payment' || 'bank_charge_received' => 'Cobro',
      'charge' || 'sync_debit' || 'bank_sync_debit' => 'Cargado',
      'transfer_received' || 'bank_transfer_received' || 'bank_transfer_delivered' => 'Transferencia recibida',
      'transfer_held' || 'bank_transfer_held' => 'Retenido',
      'transfer_cancelled' || 'bank_transfer_cancelled' => 'Devuelto',
      'handshake_initial' || 'bank_player_joined' => 'Vinculaci\u00f3n',
      'handshake_reconnect' || 'handshake_restore' || 'bank_player_reconnected' => 'Reconexi\u00f3n',
      'investment_opened' || 'bank_investment_opened' => 'Inversi\u00f3n iniciada',
      'investment_completed' || 'bank_investment_completed' => 'Inversi\u00f3n completada',
      'investment_early_withdrawal' || 'bank_investment_early_withdrawal' => 'Retiro de inversi\u00f3n',
      'bankruptcy' || 'bank_bankruptcy' => 'Bancarrota',
      'sync_credit' || 'bank_sync_credit' => 'Sincronizaci\u00f3n',
      _ => type,
    };
  }
}
