import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/core/game_transitions.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';
import 'package:monopoly_banking/screens/wallet_screen.dart';
import 'package:monopoly_banking/screens/bank/bank_settings_screen.dart';
import 'package:monopoly_banking/services/app_audit_logger.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/foreground_service.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/ws_models.dart';
import 'package:monopoly_banking/widgets/animated_players_backdrop.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';
import 'package:monopoly_banking/widgets/premium_dialog.dart';
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:monopoly_banking/widgets/transport_selector.dart';
import 'package:monopoly_banking/widgets/player_info_widget.dart';

import 'wallet/ws_bank_panel.dart';
import 'wallet/connection_panel.dart';

class BankDesktopScreen extends StatefulWidget {
  const BankDesktopScreen({super.key});

  @override
  State<BankDesktopScreen> createState() => _BankDesktopScreenState();
}

class _BankDesktopScreenState extends State<BankDesktopScreen> {
  @override
  Widget build(BuildContext context) {
    final bankColor = context.watch<SessionProvider>().color;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedPlayersBackdrop(
        bankColor: bankColor,
        child: Stack(
          children: [
            Positioned.fill(
              child: Visibility(
                visible: false,
                maintainState: true,
                child: WalletScreen(key: const ValueKey('wallet_lifecycle')),
              ),
            ),
            Positioned.fill(
              child: Visibility(
                visible: false,
                maintainState: true,
                child: BankScreen(key: const ValueKey('bank_lifecycle')),
              ),
            ),
            const _DesktopLayout(),
          ],
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatefulWidget {
  const _DesktopLayout();
  @override
  State<_DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<_DesktopLayout> {
  String? _walletFilterType;
  String _walletSortBy = 'date';
  bool _walletSortAscending = false;

  void _confirmExit() {
    final session = context.read<SessionProvider>();
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
              Navigator.pop(context);
              try {
                await P2PService().wsTransport.sendPayload({'type': 'bank_server_stopping'});
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

  void _showPlayerInfo(WsPlayer player) {
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
    final playerColor = _playerColorById(player.colorId);
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
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: playerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            player.avatarId.isNotEmpty ? player.avatarId : '\u{1F464}',
                            style: TextStyle(fontSize: 22, color: playerColor),
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
                      Tab(text: 'Datos Conexi\u00f3n'),
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
                        SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _desktopSectionHeader('Dispositivo'),
                              _desktopDetailRow('Direcci\u00f3n IP', player.address.isNotEmpty ? player.address : '-'),
                              _desktopDetailRow('ID Instalaci\u00f3n', player.deviceInstallationId.isNotEmpty ? player.deviceInstallationId : '-'),
                              const SizedBox(height: 12),
                              _desktopSectionHeader('Estado Conexi\u00f3n'),
                              _desktopDetailRow('Handshake', player.connected ? 'Completado' : 'Pendiente'),
                              const SizedBox(height: 8),
                              _desktopDetailRow('\u00daltima actividad', _format12h(player.lastSeen)),
                            ],
                          ),
                        ),
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
                          final confirm = await showGameDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Expulsar jugador'),
                              content: Text('\u00bfExpulsar a "${player.displayName}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                  child: const Text('Expulsar'),
                                ),
                              ],
                            ),
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
                        label: const Text('Sacar del juego', style: TextStyle(fontWeight: FontWeight.w800)),
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

  String _tierLabel(String tier) => switch (tier) {
        'black' => 'ULTIMATE BLACK',
        'platinum' => 'PLATINUM PRESTIGE',
        'gold' => 'GOLD MEMBERSHIP',
        _ => 'CLASSIC EDITION',
      };

  Color _tierColor(String tier) => switch (tier) {
        'standard' => const Color(0xFF90A4AE),
        'gold' => const Color(0xFFFFD700),
        'platinum' => const Color(0xFF1E88E5),
        'black' => const Color(0xFF424242),
        _ => const Color(0xFF90A4AE),
      };

  String _format12h(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Widget _desktopSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(color: kGold, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5),
      ),
    );
  }

  Widget _desktopDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _compact(double val) => formatMoney(val);

  Color _playerColorById(String colorId) {
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final wallet = context.watch<WalletController>();
    final stats = context.watch<StatsProvider>();
    final bankColor = session.color;
    final displayName = session.name.isNotEmpty ? session.name : 'Banco Monopoly';
    final history = wallet.history;

    final filteredHistory = (() {
      var result = _walletFilterType != null ? history.where((tx) => tx.type == _walletFilterType).toList() : history.toList();
      result.sort((a, b) {
        int cmp;
        if (_walletSortBy == 'amount') {
          cmp = a.amount.compareTo(b.amount);
        } else {
          cmp = a.timestamp.compareTo(b.timestamp);
        }
        return _walletSortAscending ? cmp : -cmp;
      });
      return result;
    })();

    return Column(
      children: [
        _buildAppBar(bankColor, displayName, stats),
        Expanded(
          child: Row(
            children: [
              _buildSidebar(bankColor),
              Container(width: 0, color: kBorder),
              Expanded(
                child: _buildMainContent(
                  bankColor,
                  displayName,
                  history,
                  filteredHistory,
                  stats,
                  session,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(Color bankColor, String displayName, StatsProvider stats) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 8, 20, 10),
      decoration: BoxDecoration(
        color: kBgDark.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bankColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_rounded, color: kGold, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          _appBarStat(Icons.payments_rounded, _compact(stats.totalVolume), bankColor),
          _appBarDivider(bankColor),
          _appBarStat(Icons.history_rounded, '${stats.txCount}', bankColor),
          _appBarDivider(bankColor),
          _appBarStat(Icons.flag_rounded, 'x${stats.passGoCount}', bankColor),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 28,
            color: kBorder,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: kRed, size: 18),
            tooltip: 'Cerrar Sesi\u00f3n',
            onPressed: () {
              SoundService.playClick();
              _confirmExit();
            },
          ),
        ],
      ),
    );
  }

  Widget _appBarStat(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _appBarDivider(Color color) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: color.withValues(alpha: 0.15),
    );
  }

  Widget _buildSidebar(Color bankColor) {
    return SizedBox(
      width: 340,
      child: Container(
        color: kBgDark.withValues(alpha: 0.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WsBankPanel(
                      onReiniciarWs: () async {
                        await P2PService().wsTransport.stop();
                        await P2PService().startWsServer();
                      },
                      onStopWs: () => P2PService().wsTransport.stop(),
                      onEnsureWsReady: () async {
                        try {
                          await P2PService().wsTransport.initialize();
                          return true;
                        } catch (_) {
                          return false;
                        }
                      },
                    ),
                    ConnectedPlayersPanel(
                      color: bankColor,
                      onPlayerTap: _showPlayerInfo,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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

  Widget _buildMainContent(
    Color bankColor,
    String displayName,
    List<TransactionModel> history,
    List<TransactionModel> filteredHistory,
    StatsProvider stats,
    SessionProvider session,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _DesktopOpsForm(),
          if (history.isNotEmpty || filteredHistory.isNotEmpty) _buildHistorySection(filteredHistory, history),
          if (history.isEmpty && filteredHistory.isEmpty)
            const SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_rounded, color: kTextSecondary, size: 64),
                    SizedBox(height: 16),
                    Text('Sin transacciones a\u00fan', style: TextStyle(color: kTextSecondary, fontSize: 15)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<TransactionModel> filteredHistory, List<TransactionModel> history) {
    return Container(
      constraints: const BoxConstraints(minHeight: 640),
      margin: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      decoration: BoxDecoration(
        color: kBgCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 480) {
                  return Row(
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
                        decoration: BoxDecoration(
                          color: kBgDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${filteredHistory.length}',
                          style: const TextStyle(color: kTextSecondary, fontSize: 11),
                        ),
                      ),
                      const Spacer(),
                      _buildFilterControls(history),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
                          decoration: BoxDecoration(
                            color: kBgDark,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${filteredHistory.length}',
                            style: const TextStyle(color: kTextSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildFilterControls(history),
                  ],
                );
              },
            ),
          ),
          if (filteredHistory.isEmpty && history.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: filteredHistory.length,
              itemBuilder: (_, i) => TransactionTile(tx: filteredHistory[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterControls(List<TransactionModel> history) {
    final typeValues = history.map((tx) => tx.type).where((t) => t.isNotEmpty).toSet().toList()..sort();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 740) {
          return Row(
            children: [
              SizedBox(width: 150, child: _filterDropdown(history, typeValues)),
              const SizedBox(width: 6),
              SizedBox(width: 130, child: _sortDropdown()),
              const SizedBox(width: 6),
              _sortButton(),
            ],
          );
        }
        if (constraints.maxWidth > 340) {
          return Row(
            children: [
              Expanded(child: _filterDropdown(history, typeValues)),
              const SizedBox(width: 6),
              SizedBox(width: 100, child: _sortDropdown()),
              const SizedBox(width: 6),
              _sortButton(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filterDropdown(history, typeValues),
            const SizedBox(height: 6),
            SizedBox(width: 160, child: _sortDropdown()),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: _sortButton(),
            ),
          ],
        );
      },
    );
  }

  Widget _filterDropdown(List<TransactionModel> history, List<String> typeValues) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _walletFilterType,
          isDense: true,
          hint: const Text('Todos', style: TextStyle(color: kTextSecondary, fontSize: 11)),
          dropdownColor: kBgCard,
          style: const TextStyle(color: kTextPrimary, fontSize: 11),
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 11))),
            ...typeValues.map((t) => DropdownMenuItem(value: t, child: Text(_typeLabel(t), style: const TextStyle(fontSize: 11)))),
          ],
          onChanged: (v) => setState(() => _walletFilterType = v),
        ),
      ),
    );
  }

  Widget _sortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _walletSortBy,
          isDense: true,
          dropdownColor: kBgCard,
          style: const TextStyle(color: kTextPrimary, fontSize: 11),
          items: const [
            DropdownMenuItem(value: 'date', child: Text('Fecha', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'amount', child: Text('Monto', style: TextStyle(fontSize: 11))),
          ],
          onChanged: (v) => setState(() => _walletSortBy = v!),
        ),
      ),
    );
  }

  Widget _sortButton() {
    return GestureDetector(
      onTap: () => setState(() => _walletSortAscending = !_walletSortAscending),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
        child: Icon(
          _walletSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: kTextSecondary,
          size: 14,
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    if (type.startsWith('custom_')) {
      final customId = type.substring('custom_'.length);
      final match = BankSettingsService().customOps.where((c) => c.id == customId).firstOrNull;
      return match?.name ?? 'Personalizada';
    }
    return switch (type) {
      'passGo' || 'bank_pass_go_sent' => 'GO',
      'received' || 'bank_payment_sent' => 'Recibido',
      'payment' || 'bank_charge_received' => 'Cobro',
      'charge' || 'sync_debit' => 'Cargado',
      'transfer_received' => 'Transferencia',
      'transfer_held' => 'Retenido',
      'transfer_cancelled' => 'Devuelto',
      'handshake_initial' || 'bank_player_joined' => 'Vinculaci\u00f3n',
      'handshake_reconnect' => 'Reconexi\u00f3n',
      _ => type,
    };
  }
}

class _DesktopOpsForm extends StatefulWidget {
  const _DesktopOpsForm();
  @override
  State<_DesktopOpsForm> createState() => _DesktopOpsFormState();
}

class _DesktopOpsFormState extends State<_DesktopOpsForm> {
  final _amountCtrl = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  String _selectedOp = 'payment';
  List<_OpOption>? _cachedOps;
  final Map<String, Completer<Map<String, dynamic>>> _pendingDeliveryAcks = {};
  StreamSubscription<Map<String, dynamic>>? _payloadSub;

  @override
  void initState() {
    super.initState();
    _payloadSub = P2PService().payloadStream.listen((payload) {
      if (!mounted) return;
      final type = payload['type'] as String?;
      if (type == 'bank_state_ack' || type == 'handshake_confirm') {
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null) {
          final completer = _pendingDeliveryAcks[bankTxId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    for (final c in _pendingDeliveryAcks.values) {
      if (!c.isCompleted) c.completeError(StateError('Disposed'));
    }
    _pendingDeliveryAcks.clear();
    _payloadSub?.cancel();
    _amountCtrl.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  List<_OpOption> get _operations {
    if (_cachedOps != null) return _cachedOps!;
    final settings = BankSettingsService();
    _cachedOps = <_OpOption>[
      const _OpOption(id: 'payment', label: 'Cobrar al jugador', icon: Icons.arrow_upward_rounded, color: kRed),
      const _OpOption(id: 'receive', label: 'Pagar al jugador', icon: Icons.arrow_downward_rounded, color: kGreen),
      _OpOption(id: 'passGo', label: 'Pasar por GO (${formatMoney(settings.passGoAmount.round())})', icon: Icons.flag_rounded, color: kGold),
      for (final c in settings.customOps)
        _OpOption(
            id: 'custom:${c.id}',
            label: c.name,
            icon: BankSettingsService.availableIcons[c.iconKey] ?? Icons.payments_rounded,
            color: c.isGive ? kGreen : kRed),
    ];
    return _cachedOps!;
  }

  bool _isFixedOpGive() {
    if (_selectedOp == 'passGo') return true;
    if (_selectedOp.startsWith('custom:')) {
      final customId = _selectedOp.substring('custom:'.length);
      return BankSettingsService().customOps.where((c) => c.id == customId).firstOrNull?.isGive ?? true;
    }
    return _selectedOp == 'receive';
  }

  double _fixedAmountForSelectedOp() {
    if (_selectedOp == 'passGo') return BankSettingsService().passGoAmount;
    if (_selectedOp.startsWith('custom:')) {
      final customId = _selectedOp.substring('custom:'.length);
      return BankSettingsService().customOps.where((c) => c.id == customId).firstOrNull?.amount ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kBgCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompactHeader(),
            const SizedBox(height: 16),
            _buildSpecialOperations(),
            const SizedBox(height: 16),
            _buildResponsiveOpsLayout(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: kGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.account_balance_rounded, color: kGold, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Operaciones del Banco', style: TextStyle(color: kGold, fontWeight: FontWeight.w800, fontSize: 15)),
              Text('Gestiona el capital de los jugadores', style: TextStyle(color: kTextSecondary, fontSize: 11)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded, color: kTextSecondary, size: 20),
          tooltip: 'Configuraci\u00f3n',
          onPressed: () async {
            final changed = await Navigator.of(context).push<dynamic>(GameFadeRoute(page: BankSettingsScreen()));
            if (changed == true && mounted) {
              _cachedOps = null;
              setState(() {});
            }
          },
        ),
      ],
    );
  }

  Widget _buildResponsiveOpsLayout() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final stackHorizontally = screenWidth > 990;

    if (stackHorizontally) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: _buildOpSelectorColumn()),
          const SizedBox(width: 20),
          Expanded(flex: 6, child: _buildRightPanel()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOpSelectorColumn(),
        const SizedBox(height: 16),
        _buildRightPanel(),
      ],
    );
  }

  Widget _buildOpSelectorColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('OPERACI\u00d3N', style: TextStyle(color: kTextSecondary, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 10),
        ...(_operations.map((op) => _buildOpTile(op))),
      ],
    );
  }

  Widget _buildOpTile(_OpOption op) {
    final selected = _selectedOp == op.id;
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        setState(() => _selectedOp = op.id);
        final isFixed = op.id == 'passGo' || op.id.startsWith('custom:');
        if (!isFixed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _amountFocusNode.requestFocus();
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? op.color.withValues(alpha: 0.12) : kBgDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? op.color : kBorder, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(op.icon, color: selected ? op.color : kTextSecondary, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                op.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: selected ? op.color : kTextSecondary, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            if (selected) Container(width: 6, height: 6, decoration: BoxDecoration(color: op.color, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    final isFixedOp = _selectedOp == 'passGo' || _selectedOp.startsWith('custom:');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isFixedOp) ...[
          const Text('MONTO', style: TextStyle(color: kTextSecondary, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountCtrl,
            focusNode: _amountFocusNode,
            onTap: () => SoundService.playClick(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(color: kGreen, fontSize: 20, fontWeight: FontWeight.w700),
              hintText: '0',
              hintStyle: const TextStyle(color: kBorder, fontSize: 20),
              filled: true,
              fillColor: kBgDark,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen, width: 1.5)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kRed)),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa un monto';
              final n = double.tryParse(v.replaceAll(',', ''));
              if (n == null || n <= 0) return 'Monto inv\u00e1lido';
              return null;
            },
          ),
          const SizedBox(height: 10),
          _buildQuickAmounts(),
        ],
        if (isFixedOp) _buildFixedAmountDisplay(),
        const SizedBox(height: 14),
        _buildSendButton(),
      ],
    );
  }

  Widget _buildFixedAmountDisplay() {
    final amount = _fixedAmountForSelectedOp();
    final isGive = _isFixedOpGive();
    final color = isGive ? kGreen : kRed;
    final prefix = isGive ? '+' : '-';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(isGive ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Text('$prefix${formatMoney(amount)}', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildQuickAmounts() {
    if (_selectedOp == 'passGo' || _selectedOp.startsWith('custom:')) return const SizedBox();
    const presets = [50, 100, 200, 500, 1000, 2000];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: presets.map((p) {
        return GestureDetector(
          onTap: () {
            SoundService.playClick();
            _amountCtrl.text = '$p';
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: kBgDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
            child: Text(formatMoney(p), style: const TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSendButton() {
    final op = _operations.firstWhere((o) => o.id == _selectedOp);
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending ? const AppSpinner(size: 16, color: Colors.black) : Icon(op.icon, size: 18),
        label: Text(_sending ? 'Enviando...' : op.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: op.color,
          foregroundColor: op.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildSpecialOperations() {
    return ValueListenableBuilder<int>(
      valueListenable: BankLedgerService().heldTransfersCount,
      builder: (context, count, _) {
        if (count == 0) return const SizedBox.shrink();
        final held = BankLedgerService().heldTransfers;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  const Text('TRANSFERENCIAS RETENIDAS', style: TextStyle(color: kTextSecondary, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('$count', style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...held.map((ht) => _buildHeldTransferRow(ht)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeldTransferRow(HeldTransfer ht) {
    final diff = DateTime.now().difference(ht.heldAt);
    final timeAgo = diff.inSeconds < 60
        ? 'hace ${diff.inSeconds}s'
        : diff.inMinutes < 60
            ? 'hace ${diff.inMinutes}m'
            : 'hace ${diff.inHours}h';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('De: ${ht.fromPlayerId}', style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
              Text(formatMoney(ht.amount), style: const TextStyle(color: kGold, fontWeight: FontWeight.w900, fontSize: 14)),
              Text(timeAgo, style: const TextStyle(color: kTextSecondary, fontSize: 10)),
            ],
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => _resolveHeldTransfer(ht, returnToSender: true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 30),
            ),
            child: const Text('Devolver', style: TextStyle(fontSize: 10)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: () => _resolveHeldTransfer(ht, returnToSender: false),
            style: OutlinedButton.styleFrom(
              foregroundColor: kGreen,
              side: const BorderSide(color: kGreen),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 30),
            ),
            child: const Text('Entregar', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveHeldTransfer(HeldTransfer ht, {required bool returnToSender}) async {
    if (returnToSender) {
      final confirmed = await showGameDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Devolver dinero', style: TextStyle(color: kTextPrimary)),
          content: Text('Se devolver\u00e1n ${formatMoney(ht.amount)} a ${ht.fromPlayerId}.', style: const TextStyle(color: kTextSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Devolver')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final credited = await BankLedgerService().credit(ht.fromPlayerId, ht.amount, type: 'transfer_cancelled', counterpartyId: 'Banco');
        await BankLedgerService().removeHeldTransfer(ht.id);
        if (mounted) NotificationService().show('Dinero devuelto a ${ht.fromPlayerId}', backgroundColor: Colors.orange);
        try {
          await _sendToConnectedPlayer(credited.toClientPayload());
        } on TransportUnavailableException catch (e) {
          if (mounted) NotificationService().show('Devuelto, sin confirmaci\u00f3n: ${e.transportName}', backgroundColor: Colors.orange);
        }
      } catch (e, s) {
        if (mounted) context.showFriendlyError(e, s);
      }
    } else {
      final receiver = await _selectTargetPlayer(title: 'Seleccionar receptor', excludePlayerId: ht.fromPlayerId);
      if (receiver == null) {
        if (mounted) NotificationService().show('No hay jugadores disponibles.', backgroundColor: Colors.orange);
        return;
      }
      final receiverName = receiver.displayName;
      if (!mounted) return;
      final confirmed = await showGameDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Entregar dinero', style: TextStyle(color: kTextPrimary)),
          content: Text('Se entregar\u00e1n ${formatMoney(ht.amount)} a $receiverName.', style: const TextStyle(color: kTextSecondary, height: 1.35)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white),
                child: const Text('Entregar')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final delivered = await BankLedgerService().credit(receiverName, ht.amount, type: 'transfer_received', counterpartyId: ht.fromPlayerId);
        await _sendToConnectedPlayer(delivered.toClientPayload());
        try {
          final senderNote = await BankLedgerService().credit(ht.fromPlayerId, 0, type: 'transfer_delivered', counterpartyId: receiverName);
          final senderPlayer =
              P2PService().wsTransport.connectedPlayersNotifier.value.where((p) => p.connected && p.name == ht.fromPlayerId).firstOrNull;
          if (senderPlayer != null) await _sendToConnectedPlayer(senderNote.toClientPayload());
        } catch (_) {}
        await BankLedgerService().removeHeldTransfer(ht.id);
        SoundService.playSuccess();
        HapticFeedback.mediumImpact();
        if (mounted) NotificationService().show('Dinero entregado a $receiverName', backgroundColor: kGreen);
      } catch (e, s) {
        if (mounted) context.showFriendlyError(e, s);
      }
    }
  }

  Future<WsPlayer?> _selectTargetPlayer({required String title, String? excludePlayerId}) async {
    final players = P2PService()
        .wsTransport
        .connectedPlayersNotifier
        .value
        .where((p) => p.connected && p.name.isNotEmpty && (excludePlayerId == null || p.name != excludePlayerId))
        .toList();
    return showGameDialog<WsPlayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: players.isEmpty
                ? [
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Column(children: [
                          Icon(Icons.person_off_rounded, color: kTextSecondary, size: 48),
                          SizedBox(height: 12),
                          Text('No hay jugadores disponibles.', textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13))
                        ]))
                  ]
                : players
                    .map((player) => GestureDetector(
                          onTap: () => Navigator.pop(ctx, player),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: kBgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                            child: Row(children: [
                              Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                      color: _playerColorById(player.colorId).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                  child: Center(
                                      child: Text(player.avatarId.isNotEmpty ? player.avatarId : '\u{1F464}',
                                          style: TextStyle(fontSize: 20, color: _playerColorById(player.colorId))))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(player.displayName,
                                      style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 15))),
                              const Icon(Icons.chevron_right_rounded, color: kTextSecondary, size: 20),
                            ]),
                          ),
                        ))
                    .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      ),
    );
  }

  Color _playerColorById(String colorId) {
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

  Future<void> _send() async {
    SoundService.playClick();
    if (!_formKey.currentState!.validate()) return;

    final connectedPlayers = P2PService().wsTransport.connectedPlayersNotifier.value.where((p) => p.connected && p.name.isNotEmpty).toList();
    if (connectedPlayers.isEmpty) {
      if (mounted) NotificationService().show('No hay jugadores conectados', backgroundColor: Colors.orange);
      return;
    }

    final targetPlayer = await _selectTargetPlayer(title: 'Seleccionar jugador');
    if (targetPlayer == null) return;

    setState(() => _sending = true);

    try {
      final ledger = BankLedgerService();
      final playerId = targetPlayer.displayName;

      if (_selectedOp == 'passGo') {
        final passGoAmount = BankSettingsService().passGoAmount;
        final result = await ledger.passGo(playerId);
        await _sendToConnectedPlayer(result.toClientPayload());
        SoundService.playFanfare();
        HapticFeedback.vibrate();
        NotificationService().show('$playerId pas\u00f3 por GO: +${formatMoney(passGoAmount)}', backgroundColor: kGold);
      } else if (_selectedOp.startsWith('custom:')) {
        final fixedAmount = _fixedAmountForSelectedOp();
        if (fixedAmount <= 0) throw const BankLedgerException('Monto inv\u00e1lido para la operaci\u00f3n personalizada.');
        final customId = _selectedOp.substring('custom:'.length);
        final match = BankSettingsService().customOps.where((c) => c.id == customId).firstOrNull;
        final opName = match?.name;
        final isGive = match?.isGive ?? true;
        if (isGive) {
          final result = await ledger.credit(playerId, fixedAmount, type: 'custom_$customId');
          final payload = result.toClientPayload();
          if (opName != null) payload['customOpName'] = opName;
          await _sendToConnectedPlayer(payload);
          SoundService.playSuccess();
          HapticFeedback.mediumImpact();
          NotificationService()
              .show('${opName ?? 'Operaci\u00f3n'}: +${formatMoney(fixedAmount)} a $playerId', backgroundColor: Colors.green.shade700);
        } else {
          final account = ledger.accountFor(playerId);
          if (account == null) throw const BankLedgerException('El jugador necesita completar el handshake inicial.');
          if (fixedAmount > account.balance) {
            if (!mounted) return;
            final proceed = await _confirmBankruptcy(playerId: playerId, availableBalance: account.balance, chargeAmount: fixedAmount);
            if (proceed != true) {
              NotificationService().show('Cobro cancelado', backgroundColor: Colors.orange);
              return;
            }
            final result = await ledger.markBankrupt(playerId, attemptedCharge: fixedAmount, deviceInstallationId: targetPlayer.deviceInstallationId);
            await _sendToConnectedPlayer(result.toClientPayload());
            SoundService.playSadTrombone();
            HapticFeedback.heavyImpact();
            NotificationService().show('$playerId en bancarrota.', backgroundColor: kRed);
            return;
          }
          final result = await ledger.debit(playerId, fixedAmount, type: 'custom_$customId');
          final payload = result.toClientPayload();
          if (opName != null) payload['customOpName'] = opName;
          await _sendToConnectedPlayer(payload);
          SoundService.playSadTrombone();
          HapticFeedback.heavyImpact();
          NotificationService()
              .show('${opName ?? 'Operaci\u00f3n'}: -${formatMoney(fixedAmount)} a $playerId', backgroundColor: Colors.orange.shade800);
        }
      } else {
        final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));
        if (_selectedOp == 'receive') {
          final result = await ledger.credit(playerId, amount, type: 'payment', counterpartyId: 'Banco');
          await _sendToConnectedPlayer(result.toClientPayload());
          SoundService.playSuccess();
          HapticFeedback.mediumImpact();
          NotificationService().show('Pagado ${formatMoney(amount)} a $playerId', backgroundColor: Colors.green.shade700);
        } else {
          final account = ledger.accountFor(playerId);
          if (account == null) throw const BankLedgerException('El jugador necesita completar el handshake inicial.');
          if (amount > account.balance) {
            if (!mounted) return;
            final proceed = await _confirmBankruptcy(playerId: playerId, availableBalance: account.balance, chargeAmount: amount);
            if (proceed != true) {
              NotificationService().show('Cobro cancelado', backgroundColor: Colors.orange);
              return;
            }
            final result = await ledger.markBankrupt(playerId, attemptedCharge: amount, deviceInstallationId: targetPlayer.deviceInstallationId);
            await _sendToConnectedPlayer(result.toClientPayload());
            SoundService.playSadTrombone();
            HapticFeedback.heavyImpact();
            NotificationService().show('$playerId en bancarrota.', backgroundColor: kRed);
            return;
          }
          final result = await ledger.debit(playerId, amount, type: 'charge', counterpartyId: 'Banco');
          await _sendToConnectedPlayer(result.toClientPayload());
          SoundService.playSadTrombone();
          HapticFeedback.heavyImpact();
          NotificationService().show('Cobrado ${formatMoney(amount)} a $playerId', backgroundColor: Colors.orange.shade800);
        }
      }
      if (mounted) {
        NotificationService().show('Proceso completado con $playerId', backgroundColor: kGreen);
      }
    } catch (e, s) {
      if (mounted) {
        if (e is TransportUnavailableException) {
          NotificationService().show(e.transportName, backgroundColor: kRed);
        } else {
          context.showFriendlyError(e, s);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _amountCtrl.clear();
      }
    }
  }

  Future<bool?> _confirmBankruptcy({required String playerId, required double availableBalance, required double chargeAmount}) {
    return showGameDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        icon: const Icon(Icons.warning_amber_rounded, color: kRed, size: 54),
        title: const Text('Riesgo de bancarrota', textAlign: TextAlign.center),
        content: Text(
          '$playerId dispone de ${formatMoney(availableBalance)}, pero el cobro es de ${formatMoney(chargeAmount)}. Si contin\u00faas, el jugador perder\u00e1 la partida.\n\n\u00bfDeseas declarar al jugador en bancarrota?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kTextSecondary, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            icon: const Icon(Icons.gavel_rounded),
            label: const Text('Declarar bancarrota'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendToConnectedPlayer(Map<String, dynamic> payload) async {
    AppAuditLogger.instance.event('BANK_OP', 'send_to_player', data: {'type': payload['type'], 'playerId': payload['targetPlayerId']});
    P2PService().setTransport(TransportType.ws);

    final bankTxId = payload['bankTxId'] as String?;
    final requiresConfirmation = (payload['type'] == 'bank_state' || payload['type'] == 'handshake') && bankTxId != null;
    if (!requiresConfirmation) {
      await P2PService().sendPayload(payload);
      return;
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingDeliveryAcks[bankTxId] = completer;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        await P2PService().sendPayload(payload);
        try {
          final confirmation = await completer.future.timeout(const Duration(seconds: 6));
          final expectedPlayer = payload['targetPlayerId'] as String?;
          final confirmedPlayer = confirmation['playerId'] as String?;
          final expectedBalance = (payload['balance'] as num?)?.toDouble();
          final confirmedBalance = (confirmation['appliedBalance'] as num?)?.toDouble();
          final playerMatches = expectedPlayer == null || (confirmedPlayer != null && confirmedPlayer == expectedPlayer);
          final balanceMatches = expectedBalance == null || (confirmedBalance != null && (confirmedBalance - expectedBalance).abs() < 0.001);
          if (!playerMatches || !balanceMatches) {
            throw TransportUnavailableException('El jugador respondi\u00f3, pero no confirm\u00f3 el saldo esperado.');
          }
          return;
        } on TimeoutException {
          if (attempt == 1) rethrow;
        }
      }
    } on TimeoutException {
      throw TransportUnavailableException('El jugador no confirm\u00f3 que recibi\u00f3 la operaci\u00f3n.');
    } finally {
      _pendingDeliveryAcks.remove(bankTxId);
    }
  }
}

class _OpOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  const _OpOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}
