import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';

class OdometerWidget extends StatefulWidget {
  final double value;
  final TextStyle? style;
  final Color? color;

  const OdometerWidget({
    super.key,
    required this.value,
    this.style,
    this.color,
  });

  @override
  State<OdometerWidget> createState() => _OdometerWidgetState();
}

class _OdometerWidgetState extends State<OdometerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.value;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(begin: widget.value, end: widget.value).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutExpo),
    );
  }

  @override
  void didUpdateWidget(OdometerWidget old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _prev, end: widget.value).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutExpo),
      );
      _prev = widget.value;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ??
        TextStyle(
          fontSize: 56,
          fontWeight: FontWeight.w900,
          letterSpacing: -2,
          color: widget.color ?? kGreen,
        );

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final formatted = formatMoneyAmount(_anim.value.round());
        return ShaderMask(
          shaderCallback: (bounds) {
            final color = widget.color ?? kGreen;
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.6),
                color,
                color.withValues(alpha: 0.6)
              ],
            ).createShader(bounds);
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$kMoneySymbol$formatted',
              style: base.copyWith(color: Colors.white, fontSize: 32),
              maxLines: 1,
            ),
          ),
        );
      },
    );
  }
}
