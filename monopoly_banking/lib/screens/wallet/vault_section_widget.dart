import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';

class VaultSectionWidget extends StatelessWidget {
  final Color color;
  final void Function(WalletController wallet, Color color) onInvest;
  final void Function(WalletController wallet, Color color) onWithdraw;

  const VaultSectionWidget({
    super.key,
    required this.color,
    required this.onInvest,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    return ValueListenableBuilder<double>(
        valueListenable: wallet.vaultInvestedAmount,
        builder: (context, invested, _) {
          return ValueListenableBuilder<double>(
              valueListenable: wallet.vaultGeneratedAmount,
              builder: (context, generated, _) {
                return ValueListenableBuilder<int>(
                    valueListenable: wallet.vaultCurrentPasses,
                    builder: (context, currentPasses, _) {
                      return ValueListenableBuilder<int>(
                          valueListenable: wallet.vaultTargetPasses,
                          builder: (context, targetPasses, _) {
                            final hasInvestment = invested > 0;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: kBgCard,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.security_rounded, color: Colors.blueGrey),
                                      const SizedBox(width: 8),
                                      const Text('B\u00d3VEDA DE INVERSI\u00d3N',
                                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
                                      const Spacer(),
                                      if (hasInvestment)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: targetPasses > 0 && currentPasses >= targetPasses
                                                ? kGreenGlow.withValues(alpha: 0.2)
                                                : Colors.orange.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            targetPasses > 0 && currentPasses >= targetPasses ? 'COMPLETADO' : 'EN PROCESO',
                                            style: TextStyle(
                                              color: targetPasses > 0 && currentPasses >= targetPasses ? kGreenGlow : Colors.orange,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (!hasInvestment) ...[
                                    const Text(
                                      'Invierta su dinero a plazo fijo. Obtenga altos retornos bloqueando su saldo por una determinada cantidad de cruces por GO.',
                                      style: TextStyle(color: Colors.white54, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => onInvest(wallet, color),
                                        icon: const Icon(Icons.rocket_launch_rounded),
                                        label: const Text('Comenzar Inversi\u00f3n'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: color,
                                          foregroundColor: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    )
                                  ] else ...[
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Capital Invertido', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                            Text(formatMoney(invested),
                                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            const Text('Rendimiento', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                            Text('+${formatMoney(generated)}',
                                                style: const TextStyle(color: kGreenGlow, fontSize: 20, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: _AnimatedProgressFiller(
                                              value: targetPasses > 0 ? (currentPasses / targetPasses).clamp(0.0, 1.0) : 0.0,
                                              minHeight: 8,
                                              backgroundColor: Colors.white10,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text('$currentPasses / $targetPasses GO',
                                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    if (currentPasses >= targetPasses)
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () => onWithdraw(wallet, color),
                                          icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                                          label: const Text('Retirar Ganancias'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: color,
                                            foregroundColor: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.lock_rounded, color: Colors.orange, size: 16),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Inversi\u00f3n bloqueada. Completa los pases por GO para retirar.',
                                                style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            );
                          });
                    });
              });
        });
  }
}

class _AnimatedProgressFiller extends StatefulWidget {
  final double value;
  final double minHeight;
  final Color backgroundColor;
  final Color color;

  const _AnimatedProgressFiller({
    required this.value,
    required this.minHeight,
    required this.backgroundColor,
    required this.color,
  });

  @override
  State<_AnimatedProgressFiller> createState() => _AnimatedProgressFillerState();
}

class _AnimatedProgressFillerState extends State<_AnimatedProgressFiller>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  double? _from;
  double? _to;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _to = widget.value;
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_AnimatedProgressFiller old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _current;
      _to = widget.value;
      _ctrl.forward(from: 0.0);
    }
  }

  double get _current {
    if (!_ctrl.isAnimating || _from == null) return widget.value;
    return _from! + (_to! - _from!) * _anim.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: _current.clamp(0.0, 1.0),
      minHeight: widget.minHeight,
      backgroundColor: widget.backgroundColor,
      color: widget.color,
    );
  }
}
