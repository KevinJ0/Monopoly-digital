import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';

class KickedScreen extends StatefulWidget {
  const KickedScreen({
    required this.playerName,
    super.key,
  });

  final String playerName;

  @override
  State<KickedScreen> createState() => _KickedScreenState();
}

class _KickedScreenState extends State<KickedScreen>
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
    await P2PService().wsTransport.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
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
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: visualSize * 0.8,
                                      height: visualSize * 0.8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.orange.withValues(
                                              alpha: 0.2 *
                                                  (0.6 +
                                                      0.4 *
                                                          math.sin(progress *
                                                              math.pi *
                                                              2)),
                                            ),
                                            blurRadius: 60,
                                            spreadRadius: 15,
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...List.generate(6, (index) {
                                      final p =
                                          (progress + index * 0.15) % 1.0;
                                      final opacity =
                                          (1 - p).clamp(0.0, 0.5);
                                      final xOff = math.sin(p * math.pi * 4 + index) *
                                          visualSize *
                                          0.15;
                                      final yOff = -p * visualSize * 0.55;
                                      return Positioned(
                                        left: visualSize * 0.5 +
                                            xOff -
                                            6,
                                        top: visualSize * 0.5 +
                                            yOff -
                                            6,
                                        child: Opacity(
                                          opacity: opacity,
                                          child: const Icon(
                                            Icons.block_rounded,
                                            color: Colors.orange,
                                            size: 12,
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
                                          color: Colors.orange.withValues(alpha: 0.16),
                                          border: Border.all(
                                            color: Colors.orange.withValues(alpha: 0.7),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.orange.withValues(alpha: 0.28),
                                              blurRadius: 30,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.gavel_rounded,
                                          color: Colors.orange,
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
                                          color: Colors.orange,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                    Transform.rotate(
                                      angle: 0.45,
                                      child: Container(
                                        width: visualSize * 0.73,
                                        height: math.max(5, visualSize * 0.042),
                                        decoration: BoxDecoration(
                                          color: Colors.orange,
                                          borderRadius: BorderRadius.circular(4),
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
                          const Text(
                            'EXPULSADO',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 36,
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
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'Has sido expulsado de la partida por el banco. '
                              'No podrás volver a conectarte a esta partida.',
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
                                backgroundColor: Colors.orange,
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
                                  : const Icon(Icons.arrow_back_rounded),
                              label: const Text(
                                'Volver',
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
