import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/models/transaction_model.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel tx;

  const TransactionTile({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final isReceived = tx.type == 'received' || tx.type == 'passGo';
    final color = isReceived ? kGreen : kRed;
    final icon = _iconFor(tx.type);
    final sign = isReceived ? '+' : '-';

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
          _formatDate(tx.timestamp),
          style: const TextStyle(color: kTextSecondary, fontSize: 12),
        ),
        trailing: Text(
          tx.amount.isInfinite
              ? '∞'
              : tx.amount.isNaN
                  ? 'NaN'
                  : '$sign$kMoneySymbol${tx.amount.round()}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'passGo':
        return Icons.flag_rounded;
      case 'received':
        return Icons.arrow_downward_rounded;
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
