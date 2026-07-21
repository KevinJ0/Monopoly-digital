import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/wallet/premium_card.dart';

class BalanceCardSection extends StatelessWidget {
  final double balance;
  final Color color;
  final String name;
  final int colorId;
  final List<double> history;
  final bool isBank;
  final CardTier? tier;

  const BalanceCardSection({
    super.key,
    required this.balance,
    required this.color,
    required this.name,
    required this.colorId,
    required this.history,
    required this.isBank,
    this.tier,
  });

  @override
  Widget build(BuildContext context) {
    final wallet = context.read<WalletController>();
    return ValueListenableBuilder<int>(
      valueListenable: wallet.balanceDecreaseShake,
      builder: (context, shakeCount, _) {
        return PremiumCreditCard(
          balance: balance,
          name: name,
          color: color,
          colorId: colorId,
          history: history,
          isBank: isBank,
          tier: tier,
        )
            .animate(key: ValueKey('card-$shakeCount'))
            .shake(duration: 400.ms)
            .fade();
      },
    );
  }
}
