import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/p2p_service.dart';

const _kPlayerColors = [
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFFFF7043),
  Color(0xFF00ACC1),
  Color(0xFFECEFF1),
  Color(0xFF8D6E63),
  Color(0xFF81D4FA),
  Color(0xFFF48FB1),
  Color(0xFFFFCC80),
  Color(0xFFEF9A9A),
  Color(0xFFFFF176),
  Color(0xFFA5D6A7),
  Color(0xFF5C6BC0),
];

Color _colorFromId(String colorId) {
  final i = int.tryParse(colorId) ?? 0;
  if (i >= 0 && i < _kPlayerColors.length) return _kPlayerColors[i];
  return _kPlayerColors[0];
}

class AnimatedPlayersBackdrop extends StatefulWidget {
  final Color bankColor;
  final Widget child;

  const AnimatedPlayersBackdrop({
    super.key,
    required this.bankColor,
    required this.child,
  });

  @override
  State<AnimatedPlayersBackdrop> createState() =>
      _AnimatedPlayersBackdropState();
}

class _AnimatedPlayersBackdropState extends State<AnimatedPlayersBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl;
  late final AnimationController _cycleCtrl;

  List<Color> _palette = const [];

  static const _crossfadeMs = 4000;
  static const _holdMs = 16000;

  @override
  void initState() {
    super.initState();
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);

    _cycleCtrl = AnimationController(
      vsync: this,
      duration: Duration.zero,
    );

    P2PService().wsTransport.connectedPlayersNotifier.addListener(_rebuildPalette);
    _rebuildPalette();
  }

  @override
  void didUpdateWidget(covariant AnimatedPlayersBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bankColor != widget.bankColor) _rebuildPalette();
  }

  void _rebuildPalette() {
    try {
      final players =
          P2PService().wsTransport.connectedPlayersNotifier.value;
      final colors = players
          .where((p) => p.connected && p.name.isNotEmpty)
          .map((p) => _colorFromId(p.colorId))
          .toSet()
          .toList();

      if (colors.isEmpty) colors.add(widget.bankColor);
      colors.add(const Color(0xFFE53935)); // rojo de prueba
      _palette = colors;

      debugPrint('[AnimatedPlayersBackdrop] palette=${colors.length} colors, starting cycle');
      _cycleCtrl
        ..stop()
        ..duration = Duration(milliseconds: _palette.length * (_crossfadeMs + _holdMs))
        ..repeat();
    } catch (e) {
      debugPrint('[AnimatedPlayersBackdrop] error: $e');
      _palette = [widget.bankColor, const Color(0xFFE53935)];
      _cycleCtrl
        ..stop()
        ..duration = Duration(milliseconds: _palette.length * (_crossfadeMs + _holdMs))
        ..repeat();
    }
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _cycleCtrl.dispose();
    P2PService().wsTransport.connectedPlayersNotifier.removeListener(_rebuildPalette);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: kBgDark)),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([_breatheCtrl, _cycleCtrl]),
              builder: (context, _) {
                final breath = _breatheCtrl.value;
                final breathAlpha = (0.08 + breath * 0.18) * 0.8;
                final radius = 0.7 + breath * 0.7;
                final n = _palette.length;
                if (n == 0) return const SizedBox.shrink();

                final t = _cycleCtrl.value;
                final segLen = 1.0 / n;
                final seg = (t / segLen).floorToDouble();
                final localT = (t - seg * segLen) / segLen;

                final crossfadeRatio = _crossfadeMs / (_crossfadeMs + _holdMs);
                final crossfadeT = (localT / crossfadeRatio).clamp(0.0, 1.0);
                final eased = Curves.easeInOut.transform(crossfadeT);

                final fromIdx = seg.toInt() % n;
                final toIdx = (seg.toInt() + 1) % n;
                final mixed = Color.lerp(
                  _palette[fromIdx],
                  _palette[toIdx],
                  eased,
                )!;

                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, 0.75),
                      radius: radius,
                      colors: [
                        mixed.withValues(alpha: breathAlpha + 0.15),
                        mixed.withValues(alpha: breathAlpha),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.4, 0.7],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
