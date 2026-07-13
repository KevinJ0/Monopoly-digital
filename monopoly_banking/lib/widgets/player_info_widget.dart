import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/transports/ble_transport.dart';

class PlayerInfoView extends StatelessWidget {
  final BleConnectedPlayer player;
  final double balance;
  final double volume;
  final int passGoCount;
  final int txCount;
  final String tier;
  final String tierLabel;
  final Color tierColor;
  final List<Map<String, dynamic>> transactions;

  const PlayerInfoView({
    super.key,
    required this.player,
    required this.balance,
    required this.volume,
    required this.passGoCount,
    required this.txCount,
    required this.tier,
    required this.tierLabel,
    required this.tierColor,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Tarjeta del Jugador'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColor.withValues(alpha: 0.18),
                  tierColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: tierColor.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _playerColor(player.colorId).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _playerColor(player.colorId).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      player.avatarId.isNotEmpty ? player.avatarId : '👤',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tierLabel,
                        style: TextStyle(
                          color: tierColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Nivel $tier',
                        style: TextStyle(
                          color: tierColor.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildStatsGrid(),
          const SizedBox(height: 16),
          _buildSectionHeader('Últimas Transacciones'),
          ...transactions.map((tx) => _buildTxTile(tx)),
        ],
      ),
    );
  }

  Widget _buildTxTile(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final balanceAfter = (tx['balanceAfter'] as num?)?.toDouble() ?? 0;
    final icon = _txIcon(type);
    final label = _txLabel(type);
    return ListTile(
      dense: true,
      leading: Icon(icon, color: _txColor(type), size: 20),
      title: Text(label, style: const TextStyle(color: kTextPrimary, fontSize: 13)),
      subtitle: Text(
        '${type.startsWith('withdraw') || type.startsWith('charge') ? '-' : '+'}\$${amount.toStringAsFixed(0)}  →  \$${balanceAfter.toStringAsFixed(0)}',
        style: const TextStyle(color: kTextSecondary, fontSize: 11),
      ),
    );
  }

  IconData _txIcon(String type) {
    if (type.contains('passGo')) return Icons.flag_rounded;
    if (type.contains('invest')) return Icons.trending_up_rounded;
    if (type.contains('withdraw')) return Icons.account_balance_wallet_rounded;
    if (type.contains('charge')) return Icons.arrow_upward_rounded;
    if (type.contains('payment') || type.contains('credit')) return Icons.arrow_downward_rounded;
    if (type.contains('handshake')) return Icons.handshake_rounded;
    return Icons.swap_horiz_rounded;
  }

  Color _txColor(String type) {
    if (type.contains('charge')) return kRed;
    if (type.contains('withdraw')) return kRed;
    if (type.contains('passGo')) return kGold;
    if (type.contains('invest')) return Colors.blue;
    if (type.contains('handshake')) return Colors.blue;
    return kGreen;
  }

  String _txLabel(String type) {
    if (type.contains('passGo')) return 'Paso por GO';
    if (type.contains('invest')) return 'Inversión';
    if (type.contains('withdraw')) return 'Retiro de inversión';
    if (type.contains('charge')) return 'Cobro del banco';
    if (type.contains('payment') || type.contains('credit')) return 'Pago del banco';
    if (type.contains('handshake')) return 'Conexión inicial';
    return 'Transacción';
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: kTextSecondary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
      return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
              children: [
                  _detailRow('Saldo', formatMoney(balance)),
                  _detailRow('Volumen total', formatMoney(volume)),
                  _detailRow('Pases por GO', '$passGoCount'),
                  _detailRow('Transacciones', '$txCount realizadas'),
              ]
          )
      );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _playerColor(String colorId) {
    final index = int.tryParse(colorId) ?? 0;
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
    if (index >= 0 && index < colors.length) return colors[index];
    return colors[0];
  }
}
