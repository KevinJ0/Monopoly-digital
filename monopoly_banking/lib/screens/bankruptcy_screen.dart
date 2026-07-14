import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';
import 'package:provider/provider.dart';

class BankruptcyScreen extends StatefulWidget {
  const BankruptcyScreen({
    required this.playerName,
    super.key,
  });

  final String playerName;

  @override
  State<BankruptcyScreen> createState() => _BankruptcyScreenState();
}

class _BankruptcyScreenState extends State<BankruptcyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _leaveGame() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    SoundService.playClick();
    await P2PService().shutdown();
    if (!mounted) return;
    await context.read<SessionProvider>().clearSession();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D090A),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight < 680 || constraints.maxWidth < 360;
              final veryCompact = constraints.maxHeight < 540;
              final horizontalPadding = compact ? 16.0 : 24.0;
              final verticalPadding = veryCompact
                  ? 10.0
                  : compact
                      ? 16.0
                      : 28.0;
              final visualSize = veryCompact
                  ? 104.0
                  : compact
                      ? 140.0
                      : 190.0;
              final contentWidth = math.min(
                480.0,
                math.max(240.0, constraints.maxWidth - horizontalPadding * 2),
              );

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              final progress = _controller.value;
                              final pulse =
                                  1 + math.sin(progress * math.pi * 2) * 0.035;
                              return SizedBox(
                                width: visualSize,
                                height: visualSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ...List.generate(3, (index) {
                                      final ringProgress =
                                          (progress + index / 3) % 1.0;
                                      return Container(
                                        width: visualSize *
                                            (0.48 + ringProgress * 0.47),
                                        height: visualSize *
                                            (0.48 + ringProgress * 0.47),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: kRed.withValues(
                                              alpha: (1 - ringProgress) * 0.35,
                                            ),
                                            width: 2,
                                          ),
                                        ),
                                      );
                                    }),
                                    Transform.scale(
                                      scale: pulse,
                                      child: Container(
                                        width: visualSize * 0.57,
                                        height: visualSize * 0.57,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: kRed.withValues(alpha: 0.16),
                                          border: Border.all(
                                            color: kRed.withValues(alpha: 0.7),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  kRed.withValues(alpha: 0.28),
                                              blurRadius: 30,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.account_balance_rounded,
                                          color: kRed,
                                          size: visualSize * 0.28,
                                        ),
                                      ),
                                    ),
                                    Transform.rotate(
                                      angle: -0.45,
                                      child: Container(
                                        width: visualSize * 0.73,
                                        height: math.max(5, visualSize * 0.042),
                                        decoration: BoxDecoration(
                                          color: kRed,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          SizedBox(
                              height: veryCompact
                                  ? 10
                                  : compact
                                      ? 16
                                      : 24),
                          Text(
                            'BANCARROTA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kRed,
                              fontSize: veryCompact
                                  ? 26
                                  : compact
                                      ? 31
                                      : 36,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(
                              height: veryCompact
                                  ? 3
                                  : compact
                                      ? 6
                                      : 10),
                          Text(
                            widget.playerName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kTextPrimary,
                              fontSize: veryCompact
                                  ? 17
                                  : compact
                                      ? 19
                                      : 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(
                              height: veryCompact
                                  ? 9
                                  : compact
                                      ? 14
                                      : 22),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(
                              veryCompact
                                  ? 11
                                  : compact
                                      ? 14
                                      : 18,
                            ),
                            decoration: BoxDecoration(
                              color: kRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: kRed.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'El banco ha cerrado tu cuenta y has quedado fuera de esta partida. Este dispositivo no podrá volver a ingresar hasta que el banco cierre su sesión.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: kTextSecondary,
                                fontSize: veryCompact
                                    ? 12.5
                                    : compact
                                        ? 14
                                        : 16,
                                height: veryCompact ? 1.3 : 1.45,
                              ),
                            ),
                          ),
                          SizedBox(
                              height: veryCompact
                                  ? 12
                                  : compact
                                      ? 20
                                      : 32),
                          SizedBox(
                            width: double.infinity,
                            height: veryCompact
                                ? 46
                                : compact
                                    ? 50
                                    : 56,
                            child: ElevatedButton.icon(
                              onPressed: _leaving ? null : _leaveGame,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kRed,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: _leaving
                                  ? const AppSpinner(
                                      size: 20,
                                      color: Colors.white,
                                    )
                                  : const Icon(Icons.logout_rounded),
                              label: const Text(
                                'Salir de la partida',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
