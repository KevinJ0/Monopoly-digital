import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/screens/wallet_screen.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';

class BankHomeScreen extends StatefulWidget {
  const BankHomeScreen({super.key});

  @override
  State<BankHomeScreen> createState() => _BankHomeScreenState();
}

class _BankHomeScreenState extends State<BankHomeScreen> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      body: PageView(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: const [
          WalletScreen(key: ValueKey('bank_wallet_tab')),
          BankScreen(key: ValueKey('bank_panel_tab')),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad - 4 : 8),
      decoration: BoxDecoration(
        color: kBgDark,
        border: Border(
          top: BorderSide(
            color: kGold.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(_tabs.length, (index) {
              final selected = _currentIndex == index;
              final tab = _tabs[index];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (index != _currentIndex) {
                      _pageCtrl.animateToPage(
                        index,
                        duration: 300.ms,
                        curve: Curves.easeInOutCubic,
                      );
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: 250.ms,
                    curve: Curves.easeInOutCubic,
                    margin: EdgeInsets.symmetric(
                      horizontal: selected ? 16 : 32,
                      vertical: 8,
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
                                valueListenable:
                                    BankLedgerService().heldTransfersCount,
                                builder: (context, count, _) {
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Icon(
                                        tab.icon,
                                        color: selected
                                            ? kBgDark
                                            : kTextSecondary,
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
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Colors.orange,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    '$count',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
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
              );
            }),
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
