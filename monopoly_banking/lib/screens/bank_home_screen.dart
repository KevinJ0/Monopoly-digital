import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/screens/wallet_screen.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';

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
    _TabInfo(Icons.account_balance_rounded, 'Panel Banco'),
  ];

  @override
  void initState() {
    super.initState();
    kBankTabsActive = true;
    _pageCtrl = PageController();
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
    return Container(
      margin: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 12),
      height: 66,
      decoration: BoxDecoration(
        color: kBgCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: kGreen.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
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
                duration: 300.ms,
                curve: Curves.easeInOutCubic,
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected
                      ? kGreen.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: selected
                      ? Border.all(color: kGreen.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.0 : 0.88,
                      duration: 300.ms,
                      curve: Curves.easeOutBack,
                      child: Icon(
                        tab.icon,
                        color: selected ? kGreen : kTextSecondary,
                        size: selected ? 22 : 20,
                      ),
                    ),
                    AnimatedSize(
                      duration: 250.ms,
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(width: selected ? 8 : 0),
                    ),
                    if (selected)
                      Text(
                        tab.label,
                        style: const TextStyle(
                          color: kGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ).animate().fadeIn(duration: 200.ms).slideX(
                            begin: -0.1,
                            duration: 250.ms,
                            curve: Curves.easeOutCubic,
                          ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo(this.icon, this.label);
}
