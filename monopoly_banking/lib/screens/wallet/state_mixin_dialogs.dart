part of '../wallet_screen.dart';

mixin _WalletDialogs on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;
  Future<void> _safeShowFriendlyError(dynamic error, [StackTrace? stack]) async {
    final friendly = await ErrorTranslatorService().translate(error, stack);
    if (!mounted) return;
    if (friendly.severity == ErrorSeverity.error || friendly.severity == ErrorSeverity.critical) {
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

  void _openBankruptcyScreen() {
    if (_self._bankruptcyScreenOpen || !mounted) return;
    final session = context.read<SessionProvider>();
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

  void _confirmExit(SessionProvider session) {
    _confirmBankExit(session);
  }

  void _confirmBankExit(SessionProvider session) {
    showPremiumDialog(
      context: context,
      child: AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('\u00bfCerrar sesi\u00f3n?', style: TextStyle(color: kTextPrimary)),
        content: const Text(
          'Se borrar\u00e1n todos los datos de esta partida y volver\u00e1s a la selecci\u00f3n de roles.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(context);
            },
            child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() => _self._isExiting = true);
              Navigator.pop(context);
              try {
                await P2PService().wsTransport.sendPayload({
                  'type': 'bank_server_stopping',
                });
              } catch (_) {}
              await P2PService().wsTransport.stop();
              try {
                await BankForegroundService().stop();
              } catch (_) {}
              await session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cerrar Sesi\u00f3n'),
          ),
        ],
      ),
    );
  }

  void _showPlayerInfoDialog(WsPlayer player) {
    final ledger = BankLedgerService();
    final account = ledger.accountFor(player.displayName);
    final transactions = ledger.transactionHistory.where((tx) => tx['playerId'] == player.displayName).toList();
    final volume = transactions.fold<double>(
      0,
      (sum, tx) => sum + (((tx['amount'] as num?)?.toDouble() ?? 0).abs()),
    );
    final passGoCount = transactions.where((tx) => tx['type'] == 'passGo').length;
    final txCount = transactions.length;
    final balance = account?.balance ?? 0;
    final playerColor = _playerColor(player.colorId);
    final avatar = player.avatarId;
    final tier = _playerTier(balance);
    final tierLabel = _tierLabel(tier);
    final tierColor = _tierColor(tier);

    showGameDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                            style: TextStyle(fontSize: 20, color: playerColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold),
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
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await _confirmAction(
                            title: 'Expulsar jugador',
                            message:
                                '\u00bfEst\u00e1s seguro de que deseas expulsar a "${player.displayName}" de la partida? No podr\u00e1 reconectarse hasta que inicies una nueva sesi\u00f3n.',
                            confirmLabel: 'Expulsar',
                          );
                          if (confirm != true || !ctx.mounted) return;
                          Navigator.pop(ctx);
                          final installationId = player.deviceInstallationId;
                          if (installationId.isNotEmpty) {
                            await BankLedgerService().banDevice(installationId, player.displayName);
                          }
                          await P2PService().sendPayload({
                            'type': 'kick',
                            'targetPlayerId': player.displayName,
                            'playerId': player.displayName,
                          });
                        },
                        icon: const Icon(Icons.gavel_rounded, size: 18),
                        label: const Text(
                          'Sacar del juego',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
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
      Color(0xFF8D6E63),
      Color(0xFF81D4FA),
      Color(0xFFF48FB1),
      Color(0xFFFFCC80),
      Color(0xFFEF9A9A),
      Color(0xFFFFF176),
      Color(0xFFA5D6A7),
      Color(0xFF5C6BC0),
    ];
    final index = int.tryParse(colorId) ?? 0;
    if (index >= 0 && index < colors.length) return colors[index];
    return colors[0];
  }

  Widget _buildConnectionInfoTab(WsPlayer player) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Dispositivo'),
          _detailRow('Direcci\u00f3n IP', player.address.isNotEmpty ? player.address : '-'),
          _detailRow('ID Instalaci\u00f3n', player.deviceInstallationId.isNotEmpty ? player.deviceInstallationId : '-'),
          const SizedBox(height: 12),
          _buildSectionHeader('Estado Conexi\u00f3n'),
          _detailRow('Handshake', player.connected ? 'Completado' : 'Pendiente'),
          const SizedBox(height: 12),
          _detailRow('\u00daltima actividad', _format12h(player.lastSeen)),
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
              style: const TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.w500),
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
    return showGameDialog<bool>(
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

  String _format12h(DateTime dt) {
    final h = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}
