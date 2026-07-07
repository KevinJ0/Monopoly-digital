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
      'investment_completed' ||
      'investment_early_withdrawal' ||
      'bank_charge_received' =>
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
        return Icons.flag_rounded;
      case 'received':
      case 'payment':
      case 'transfer_received':
      case 'transfer_cancelled':
        return Icons.arrow_downward_rounded;
      case 'charge':
      case 'transfer_held':
        return Icons.arrow_upward_rounded;
      case 'bank_charge_received':
        return Icons.call_received_rounded;
      case 'bank_player_joined':
      case 'bank_player_reconnected':
      case 'handshake_initial':
      case 'handshake_reconnect':
      case 'handshake_restore':
        return Icons.person_add_alt_1_rounded;
      case 'bank_bankruptcy':
        return Icons.gavel_rounded;
      default:
        return Icons.arrow_upward_rounded;
    }
  }

  String _labelFor(String type) {
    switch (type) {
      case 'passGo':
        return 'Pasar por GO';
      case 'received':
        return 'Cobro recibido';
      case 'payment':
        return 'Pago recibido del banco';
      case 'charge':
        return 'Cobro realizado por el banco';
      case 'transfer_received':
        return 'Transferencia recibida';
      case 'transfer_held':
        return 'Transferencia enviada';
      case 'transfer_cancelled':
        return 'Transferencia devuelta';
      case 'investment_opened':
        return 'Dinero invertido';
      case 'investment_completed':
        return 'Inversión completada';
      case 'investment_early_withdrawal':
        return 'Retiro anticipado';
      case 'handshake_initial':
        return 'Vinculación inicial';
      case 'handshake_reconnect':
      case 'handshake_restore':
        return 'Sesión restaurada';
      case 'bankruptcy':
        return 'Bancarrota';
      case 'bank_payment_sent':
        return 'Pago al jugador';
      case 'bank_charge_received':
        return 'Cobro al jugador';
      case 'bank_pass_go_sent':
        return 'Pago por pasar GO';
      case 'bank_player_joined':
        return 'Jugador vinculado';
      case 'bank_player_reconnected':
        return 'Jugador reconectado';
      case 'bank_bankruptcy':
        return 'Jugador en bancarrota';
      default:
        return 'Pago enviado';
    }
  }

  String _formatDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year}  $h:$m';
  }
}

enum _TransactionDirection { received, sent, neutral }
