import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:money_manager/core/constants.dart';
import 'package:money_manager/providers/session_provider.dart';
import 'package:money_manager/services/p2p_service.dart';
import 'package:money_manager/services/sound_service.dart';
import 'package:money_manager/widgets/app_spinner.dart';
import 'package:provider/provider.dart';

class WinnerScreen extends StatefulWidget {
  const WinnerScreen({
    required this.playerName,
    super.key,
  });

  final String playerName;

  @override
  State<WinnerScreen> createState() => _WinnerScreenState();
}

class _WinnerScreenState extends State<WinnerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final ConfettiController _confettiCtrl;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 10));
    _confettiCtrl.play();
    SoundService.playFanfare();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _goToRoleSelection() {
    if (_leaving) return;
    setState(() => _leaving = true);
    SoundService.playClick();
    P2PService().shutdown();
    context.read<SessionProvider>().clearSession();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A1A),
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
                  ? 100.0
                  : compact
                      ? 130.0
                      : 170.0;
              final contentWidth = math.min(
                480.0,
                math.max(240.0, constraints.maxWidth - horizontalPadding * 2),
              );

              return Stack(
                children: [
                  Padding(
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
                                      1 + math.sin(progress * math.pi * 2) * 0.04;
                                  final rotate = progress * math.pi * 2;
                                  return SizedBox(
                                    width: visualSize,
                                    height: visualSize,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: visualSize * 0.85,
                                          height: visualSize * 0.85,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: kGold.withValues(
                                                  alpha: 0.15 *
                                                      (0.5 +
                                                          0.5 *
                                                              math.sin(progress *
                                                                  math.pi *
                                                                  2)),
                                                ),
                                                blurRadius: 60,
                                                spreadRadius: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                        ...List.generate(8, (index) {
                                          final p =
                                              (progress + index * 0.125) % 1.0;
                                          final opacity =
                                              (1 - p).clamp(0.0, 0.6);
                                          final angle = index *
                                                  0.785 +
                                              p * math.pi * 2;
                                          final dist = p * visualSize * 0.5;
                                          final xOff =
                                              math.cos(angle) * dist;
                                          final yOff =
                                              math.sin(angle) * dist;
                                          return Positioned(
                                            left: visualSize * 0.5 +
                                                xOff -
                                                6,
                                            top: visualSize * 0.5 +
                                                yOff -
                                                6,
                                            child: Opacity(
                                              opacity: opacity,
                                              child: Icon(
                                                Icons.star_rounded,
                                                color: kGold,
                                                size: 10,
                                              ),
                                            ),
                                          );
                                        }),
                                        Transform.scale(
                                          scale: pulse,
                                          child: Container(
                                            width: visualSize * 0.6,
                                            height: visualSize * 0.6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: const SweepGradient(
                                                colors: [
                                                  Color(0xFFFFD700),
                                                  Color(0xFFFFA500),
                                                  Color(0xFFFFD700),
                                                  Color(0xFFFFEC8B),
                                                  Color(0xFFFFD700),
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: kGold
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: 40,
                                                  spreadRadius: 10,
                                                ),
                                              ],
                                            ),
                                            child: Transform.rotate(
                                              angle: rotate,
                                              child: const Icon(
                                                Icons.emoji_events_rounded,
                                                color: Color(0xFF1A1200),
                                                size: 56,
                                              ),
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
                                      ? 8
                                      : compact
                                          ? 14
                                          : 22),
                              Text(
                                '\u00a1FELICIDADES!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: kGold,
                                  fontSize: veryCompact
                                      ? 28
                                      : compact
                                          ? 34
                                          : 42,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
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
                                      ? 20
                                      : compact
                                          ? 24
                                          : 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(
                                  height: veryCompact
                                      ? 2
                                      : compact
                                          ? 4
                                          : 8),
                              Text(
                                '\u00a1ERES EL GANADOR!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: kGold,
                                  fontSize: veryCompact
                                      ? 14
                                      : compact
                                          ? 18
                                          : 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 4,
                                ),
                              ),
                              SizedBox(
                                  height: veryCompact
                                      ? 10
                                      : compact
                                          ? 16
                                          : 24),
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
                                  color: kGold.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: kGold.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  'Has sobrevivido a todos tus oponentes y te coronas como el ganador absoluto de esta partida.',
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
                                      ? 14
                                      : compact
                                          ? 22
                                          : 36),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 180,
                                    height: veryCompact
                                        ? 48
                                        : compact
                                            ? 52
                                            : 58,
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          _leaving ? null : _goToRoleSelection,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kGold,
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30),
                                        ),
                                        elevation: 8,
                                        shadowColor:
                                            kGold.withValues(alpha: 0.5),
                                      ),
                                      icon: _leaving
                                          ? const AppSpinner(
                                              size: 20, color: Colors.black)
                                          : const Icon(
                                              Icons.home_rounded,
                                              size: 20,
                                            ),
                                      label: Text(
                                        'Volver al inicio',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: veryCompact ? 13 : 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConfettiWidget(
                      confettiController: _confettiCtrl,
                      blastDirectionality: BlastDirectionality.explosive,
                      shouldLoop: true,
                      colors: const [
                        kGold,
                        Color(0xFFFFA500),
                        Color(0xFFFFEC8B),
                        Colors.white,
                        Color(0xFFFF6B6B),
                        Color(0xFFFF69B4),
                      ],
                      numberOfParticles: 30,
                      gravity: 0.08,
                      maxBlastForce: 20,
                      minBlastForce: 5,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
