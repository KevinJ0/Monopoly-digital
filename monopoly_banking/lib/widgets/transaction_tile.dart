import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/models/transaction_model.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel tx;

  const TransactionTile({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final direction = _directionFor(tx.type);
    final color = switch (direction) {
      _TransactionDirection.received => kGreen,
      _TransactionDirection.sent => kRed,
      _TransactionDirection.neutral => kGold,
    };
    final icon = _iconFor(tx.type);
    final sign = switch (direction) {
      _TransactionDirection.received => '+',
      _TransactionDirection.sent => '-',
      _TransactionDirection.neutral => '',
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: kBgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          _labelFor(tx.type),
          style: const TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          tx.counterpartyId?.trim().isNotEmpty == true
              ? '${tx.counterpartyId} · ${_formatDate(tx.timestamp)}'
              : _formatDate(tx.timestamp),
          style: const TextStyle(color: kTextSecondary, fontSize: 12),
        ),
        trailing: Text(
          '$sign${formatMoney(tx.amount.abs())}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  _TransactionDirection _directionFor(String type) {
    return switch (type) {
      'received' ||
      'payment' ||
      'passGo' ||
      'transfer_received' ||
      'transfer_cancelled' ||
      'transfer_delivered' ||
      'sync_credit' ||
      'investment_completed' ||
      'investment_early_withdrawal' ||
      'bank_payment_sent' ||
      'bank_pass_go_sent' ||
      'bank_charge_received' ||
      'bank_transfer_received' ||
      'bank_transfer_cancelled' ||
      'bank_transfer_delivered' ||
      'bank_sync_credit' ||
      'bank_sync_debit' ||
      'bank_investment_completed' ||
      'bank_investment_early_withdrawal' =>
        _TransactionDirection.received,
      'handshake_initial' ||
      'handshake_reconnect' ||
      'handshake_restore' ||
      'bank_player_joined' ||
      'bank_player_reconnected' =>
        _TransactionDirection.neutral,
      _ => _TransactionDirection.sent,
    };
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'passGo':
      case 'bank_pass_go_sent':
        return Icons.flag_rounded;
      case 'received':
      case 'payment':
      case 'bank_payment_sent':
      case 'transfer_received':
      case 'transfer_cancelled':
      case 'transfer_delivered':
      case 'bank_transfer_received':
      case 'bank_transfer_cancelled':
      case 'bank_transfer_delivered':
        return Icons.arrow_downward_rounded;
      case 'charge':
      case 'transfer_held':
      case 'bank_transfer_held':
        return Icons.lock_outline_rounded;
      case 'bank_charge_received':
        return Icons.call_received_rounded;
      case 'bank_player_joined':
      case 'bank_player_reconnected':
      case 'handshake_initial':
      case 'handshake_reconnect':
      case 'handshake_restore':
        return Icons.person_add_alt_1_rounded;
      case 'investment_opened':
      case 'bank_investment_opened':
        return Icons.trending_up_rounded;
      case 'investment_completed':
      case 'investment_early_withdrawal':
      case 'bank_investment_completed':
      case 'bank_investment_early_withdrawal':
        return Icons.trending_up_rounded;
      case 'bank_bankruptcy':
        return Icons.gavel_rounded;
      case 'sync_credit':
      case 'sync_debit':
      case 'bank_sync_credit':
      case 'bank_sync_debit':
        return Icons.sync_rounded;
      default:
        return Icons.arrow_upward_rounded;
    }
  }

  String _labelFor(String type) {
    switch (type) {
      case 'passGo':
      case 'bank_pass_go_sent':
        return 'Pasar por GO';
      case 'received':
        return 'Cobro recibido';
      case 'payment':
      case 'bank_payment_sent':
        return 'Pago del banco';
      case 'charge':
      case 'bank_charge_received':
        return 'Cobro del banco';
      case 'transfer_received':
      case 'bank_transfer_received':
        return 'Transferencia recibida';
      case 'transfer_held':
      case 'bank_transfer_held':
        return 'Dinero retenido';
      case 'transfer_cancelled':
      case 'bank_transfer_cancelled':
        return 'Transferencia devuelta';
      case 'transfer_delivered':
      case 'bank_transfer_delivered':
        return 'Transferencia entregada';
      case 'investment_opened':
      case 'bank_investment_opened':
        return 'Inversión iniciada';
      case 'investment_completed':
      case 'bank_investment_completed':
        return 'Inversión completada';
      case 'investment_early_withdrawal':
      case 'bank_investment_early_withdrawal':
        return 'Retiro de inversión';
      case 'handshake_initial':
        return 'Vinculación inicial';
      case 'handshake_reconnect':
      case 'handshake_restore':
      case 'bank_player_joined':
      case 'bank_player_reconnected':
        return 'Conexión con el banco';
      case 'bankruptcy':
      case 'bank_bankruptcy':
        return 'Bancarrota';
      case 'sync_credit':
      case 'sync_debit':
      case 'bank_sync_credit':
      case 'bank_sync_debit':
        return 'Sincronización con el banco';
      default:
        return type;
    }
  }

  String _formatDate(DateTime dt) {
    final h = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.day}/${dt.month}/${dt.year}  $h:$m $ampm';
  }
}

enum _TransactionDirection { received, sent, neutral }
