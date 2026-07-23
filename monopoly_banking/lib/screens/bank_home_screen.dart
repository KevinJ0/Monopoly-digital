import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/screens/wallet_screen.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/widgets/animated_players_backdrop.dart';

class BankHomeScreen extends StatefulWidget {
  const BankHomeScreen({super.key});

  @override
  State<BankHomeScreen> createState() => _BankHomeScreenState();
}

class _BankHomeScreenState extends State<BankHomeScreen> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;
  bool _isAnimating = false;

  static const _tabs = [
    _TabInfo(Icons.account_balance_wallet_rounded, 'Billetera'),
    _TabInfo(Icons.dashboard_rounded, 'Operaciones'),
  ];

  @override
  void initState() {
    super.initState();
    kBankTabsActive = true;
    _pageCtrl = PageController();
    BankLedgerService().initHeldTransfersCount();
    BankSettingsService().load();
    BankLedgerService().transactionHistory;
  }

  @override
  void dispose() {
    kBankTabsActive = false;
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (_isAnimating || index == _currentIndex) return;
    setState(() => _isAnimating = true);
    _pageCtrl
        .animateToPage(index, duration: 300.ms, curve: Curves.easeInOutCubic)
        .then((_) {
      if (mounted) setState(() => _isAnimating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bankColor = context.watch<SessionProvider>().color;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AnimatedPlayersBackdrop(
        bankColor: bankColor,
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (_isAnimating) return;
            final v = details.primaryVelocity ?? 0;
            if (v < -100 && _currentIndex < _tabs.length - 1) {
              _goToPage(_currentIndex + 1);
            } else if (v > 100 && _currentIndex > 0) {
              _goToPage(_currentIndex - 1);
            }
          },
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentIndex = i),
            children: const [
              WalletScreen(key: ValueKey('bank_wallet_tab')),
              BankScreen(key: ValueKey('bank_panel_tab')),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: EdgeInsets.only(bottom: 30),
      decoration: const BoxDecoration(
        color: kBgDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: kGold,
            width: 2,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 45,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(_tabs.length, (index) {
                final selected = _currentIndex == index;
                final tab = _tabs[index];
                return Expanded(
                    child: Center(
                  child: GestureDetector(
                    onTap: () => _goToPage(index),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: 250.ms,
                      curve: Curves.easeInOutCubic,
                      margin: EdgeInsets.symmetric(
                        horizontal: selected ? 16 : 32,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                colors: [Color(0xFFE2B84D), Color(0xFFB8860B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          index == 1
                              ? ValueListenableBuilder<int>(
                                  valueListenable: BankLedgerService().heldTransfersCount,
                                  builder: (context, count, _) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 0),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(
                                            tab.icon,
                                            color: selected ? kBgDark : kTextSecondary,
                                            size: 20,
                                          ),
                                          if (count > 0)
                                            Positioned(
                                              right: -6,
                                              top: -6,
                                              child: TweenAnimationBuilder<double>(
                                                tween: Tween(begin: 0, end: 1),
                                                duration: 300.ms,
                                                curve: Curves.elasticOut,
                                                builder: (context, scale, _) {
                                                  return Transform.scale(
                                                    scale: scale,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: const BoxDecoration(
                                                        color: Colors.orange,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Text(
                                                        '$count',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : Icon(
                                  tab.icon,
                                  color: selected ? kBgDark : kTextSecondary,
                                  size: 20,
                                ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            Text(
                              tab.label,
                              style: const TextStyle(
                                color: kBgDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ));
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo(this.icon, this.label);
}
