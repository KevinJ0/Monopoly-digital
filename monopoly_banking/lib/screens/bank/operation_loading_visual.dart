part of '../bank_screen.dart';

class _OperationLoadingVisual extends StatefulWidget {
  const _OperationLoadingVisual({
    required this.completed,
    required this.failed,
    required this.transportType,
    required this.failedIcon,
    required this.failedColor,
  });

  final bool completed;
  final bool failed;
  final TransportType transportType;
  final IconData failedIcon;
  final Color failedColor;

  @override
  State<_OperationLoadingVisual> createState() =>
      _OperationLoadingVisualState();
}

class _OperationLoadingVisualState extends State<_OperationLoadingVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingColor = Colors.blue;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      child: widget.failed
          ? Container(
              key: const ValueKey('failed'),
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.failedColor.withValues(alpha: 0.14),
                border: Border.all(
                  color: widget.failedColor.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.failedColor.withValues(alpha: 0.24),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                widget.failedIcon,
                color: widget.failedColor,
                size: 64,
              ),
            )
          : widget.completed
              ? Container(
                  key: const ValueKey('completed'),
                  width: 136,
                  height: 136,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGreen.withValues(alpha: 0.14),
                    border: Border.all(color: kGreen.withValues(alpha: 0.55)),
                    boxShadow: [
                      BoxShadow(
                        color: kGreen.withValues(alpha: 0.28),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: kGreen,
                    size: 64,
                  ),
                )
              : SizedBox(
                  key: const ValueKey('waiting'),
                  width: 136,
                  height: 136,
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (context, _) {
                      final pulse = _pulseCtrl.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          _PulseRing(
                            progress: pulse,
                            delay: 0,
                            color: waitingColor,
                          ),
                          _PulseRing(
                            progress: pulse,
                            delay: 0.33,
                            color: waitingColor,
                          ),
                          _PulseRing(
                            progress: pulse,
                            delay: 0.66,
                            color: waitingColor,
                          ),
                          Positioned(
                            left: 14,
                            child: Icon(
                              Icons.account_balance_rounded,
                              color: kGold,
                              size: 48,
                            ),
                          ),
                          Positioned(
                            right: 8 + (30 * pulse),
                            child: Transform.rotate(
                              angle: -0.10 * math.sin(pulse * math.pi),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: kBgCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: waitingColor,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          waitingColor.withValues(alpha: 0.3),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.smartphone_rounded,
                                  color: waitingColor,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: waitingColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}
