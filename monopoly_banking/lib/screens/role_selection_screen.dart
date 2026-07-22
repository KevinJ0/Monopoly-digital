import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final AnimationController _bgAnimCtrl;
  int _bgCycle = 0;

  final AudioPlayer _musicPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _bgAnimCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20));
    _bgAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _bgCycle++;
        _bgAnimCtrl.forward(from: 0);
      }
    });
    _bgAnimCtrl.forward();
    WidgetsBinding.instance.addObserver(this);
    _playBackgroundMusic();
  }

  Future<void> _playBackgroundMusic() async {
    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.play(AssetSource('sounds/theme.mp3'), volume: 0.3);
    } catch (e) {
      // Ignore if sound not found
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeCtrl.dispose();
    _bgAnimCtrl.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _musicPlayer.pause();
    } else if (state == AppLifecycleState.resumed) {
      _musicPlayer.resume();
    }
  }

  Future<void> _pickRole(String role) async {
    if (role == 'banco') {
      const avatarId = '🏦';
      const colorId = '4';
      final session = context.read<SessionProvider>();
      try {
        await session.createSession(
          role: role,
          avatarId: avatarId,
          colorId: colorId,
          initialBalance: double.infinity,
          name: 'Banco',
        );
      } catch (e, s) {
        if (mounted) context.showFriendlyError(e, s);
        return;
      }
      if (mounted) setState(() {});
      return;
    }

    // Cliente: create placeholder session, then connect to bank.
    // Bank decides if device is new → onboarding, or returning → handshake.
    final session = context.read<SessionProvider>();
    if (session.isHandshakeDone) {
      session.cancelGoHome();
      return;
    }
    await session.createSession(
      role: role,
      avatarId: '👤',
      colorId: '0',
      initialBalance: 0,
      name: '',
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmExitApp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Salir de la app?', style: TextStyle(color: kTextPrimary)),
        content: const Text(
          'Se cerrará Monopoly Banking.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final didPop = await Navigator.of(context).maybePop();
      if (!didPop) {
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExitApp();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: PlayerColorBackdrop(
          color: kGreen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _bgAnimCtrl,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _MonopolyBackgroundPainter(
                        animationValue: _bgAnimCtrl.value + _bgCycle,
                      ),
                    );
                  },
                ),
              ),
              // (reserved for future actions)
              FadeTransition(
                opacity: _fade,
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const AnimatedEntry(
                              delay: Duration(milliseconds: 200),
                              child: _HeaderWidget(),
                            ),
                            const SizedBox(height: 32),
                            AnimatedEntry(
                              delay: const Duration(milliseconds: 400),
                              child: _buildBankSection(),
                            ),
                            const SizedBox(height: 10),
                            AnimatedEntry(
                              delay: const Duration(milliseconds: 600),
                              child: _buildClientSection(),
                            ),
                            const SizedBox(height: 48),
                            Text(
                              'BETA v1.0.0',
                              style: TextStyle(
                                color: kTextSecondary.withValues(alpha: 0.5),
                                fontSize: 12,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBankSection() {
    return Column(
      children: [
        _RoleButton(
          label: 'SER EL BANCO',
          subtitle: 'Control total de la partida',
          icon: Icons.account_balance_rounded,
          color: const Color(0xFFB8860B),
          onTap: () => _pickRole('banco'),
        ),
      ],
    );
  }

  Widget _buildClientSection() {
    return Column(
      children: [
        _RoleButton(
          label: 'ENTRAR COMO JUGADOR',
          subtitle: 'Recibe capital al vincular con Banca',
          icon: Icons.person_rounded,
          color: kGreen,
          onTap: () => _pickRole('cliente'),
        ),
      ],
    );
  }
}

class _RoleButton extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_RoleButton> createState() => _RoleButtonState();
}
class _RoleButtonState extends State<_RoleButton>
    with TickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  final GlobalKey _buttonKey = GlobalKey();
  bool _isExpanding = false;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapUp(TapUpDetails details) async {
    _scaleCtrl.animateTo(1.0);
    SoundService.playClick();

    setState(() => _isExpanding = true);

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      widget.onTap();
      return;
    }

    final pos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final center = Offset(pos.dx + size.width / 2, pos.dy + size.height / 2);

    const iconContainerSize = 52.0;
    final startRect = Rect.fromCenter(
      center: center,
      width: iconContainerSize,
      height: iconContainerSize,
    );

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => _ExpandOverlay(
        icon: widget.icon,
        color: widget.color,
        startRect: startRect,
        onExpanded: widget.onTap,
        onComplete: () => entry?.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!_isExpanding) _scaleCtrl.animateTo(0.95);
      },
      onTapUp: _onTapUp,
      onTapCancel: () {
        if (!_isExpanding) _scaleCtrl.animateTo(1.0);
      },
      child: AnimatedBuilder(
        animation: _scaleCtrl,
        builder: (context, child) => Transform.scale(
          scale: _scaleCtrl.value,
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              key: _buttonKey,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.color.withValues(alpha: 0.2),
                    widget.color.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: AnimatedOpacity(
                opacity: _isExpanding ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.color,
                            widget.color.withValues(alpha: 0.55),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandOverlay extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Rect startRect;
  final VoidCallback onExpanded;
  final VoidCallback onComplete;

  const _ExpandOverlay({
    required this.icon,
    required this.color,
    required this.startRect,
    required this.onExpanded,
    required this.onComplete,
  });

  @override
  State<_ExpandOverlay> createState() => _ExpandOverlayState();
}

class _ExpandOverlayState extends State<_ExpandOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _progress = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeInOut);
    _expandCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onExpanded();
        Future.delayed(const Duration(milliseconds: 500), () {
          _fadeCtrl.forward();
        });
      }
    });
    _fadeCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
    _expandCtrl.forward();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxDim = math.max(screenSize.width, screenSize.height) * 1.5;

    return AnimatedBuilder(
      animation: Listenable.merge([_progress, _fadeCtrl]),
      builder: (context, _) {
        final t = _progress.value;
        final opacity = 1.0 - _fadeCtrl.value;

        final startCenter = Offset(
          widget.startRect.left + widget.startRect.width / 2,
          widget.startRect.top + widget.startRect.height / 2,
        );
        final screenCenter =
            Offset(screenSize.width / 2, screenSize.height / 2);

        final moveProgress = (t / 0.2).clamp(0.0, 1.0);
        final expandProgress = ((t - 0.2) / 0.8).clamp(0.0, 1.0);

        final currentCenter =
            Offset.lerp(startCenter, screenCenter, moveProgress)!;
        final currentSize = lerpDouble(
          math.max(widget.startRect.width, widget.startRect.height),
          maxDim,
          expandProgress,
        )!;
        final borderRadius = lerpDouble(14, maxDim / 2, expandProgress)!;
        final iconSize =
            lerpDouble(32.0, screenSize.width * 0.2, expandProgress)!;
        const bgAlpha = 0.5;

        return Opacity(
          opacity: opacity,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Container(color: Colors.black.withValues(alpha: bgAlpha)),
                Positioned(
                  left: currentCenter.dx - currentSize / 2,
                  top: currentCenter.dy - currentSize / 2,
                  width: currentSize,
                  height: currentSize,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.color,
                          widget.color
                              .withValues(alpha: lerpDouble(0.55, 1.0, expandProgress)!),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(borderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color
                            .withValues(alpha: 0.35 * (1 - expandProgress)),
                        blurRadius: 12 * (1 - expandProgress),
                        spreadRadius: 1 * (1 - expandProgress),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(widget.icon,
                          color: Colors.white, size: iconSize),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FloatingEmoji {
  final String emoji;
  final double size;
  final double opacity;
  final double speedX;
  final double speedY;
  final double rotationSpeed;
  final double startX;
  final double startY;

  const _FloatingEmoji({
    required this.emoji,
    required this.size,
    required this.opacity,
    required this.speedX,
    required this.speedY,
    required this.rotationSpeed,
    required this.startX,
    required this.startY,
  });
}

const _emojis = [
  _FloatingEmoji(emoji: '\u{1F4B0}', size: 30, opacity: 0.18, speedX: 0.12, speedY: 0.04, rotationSpeed: 0.3, startX: 0.0, startY: 0.0),
  _FloatingEmoji(emoji: '\u{1F4B5}', size: 26, opacity: 0.15, speedX: -0.08, speedY: 0.06, rotationSpeed: -0.4, startX: 0.3, startY: 0.1),
  _FloatingEmoji(emoji: '\u{1F4B2}', size: 28, opacity: 0.20, speedX: 0.15, speedY: -0.03, rotationSpeed: 0.25, startX: 0.6, startY: 0.2),
  _FloatingEmoji(emoji: '\u{1F3E0}', size: 32, opacity: 0.14, speedX: -0.06, speedY: 0.08, rotationSpeed: -0.2, startX: 0.1, startY: 0.4),
  _FloatingEmoji(emoji: '\u{1F3E8}', size: 36, opacity: 0.12, speedX: 0.10, speedY: -0.05, rotationSpeed: 0.15, startX: 0.5, startY: 0.6),
  _FloatingEmoji(emoji: '\u{1F682}', size: 28, opacity: 0.16, speedX: -0.12, speedY: 0.02, rotationSpeed: -0.35, startX: 0.8, startY: 0.3),
  _FloatingEmoji(emoji: '\u{1F3B2}', size: 24, opacity: 0.22, speedX: 0.07, speedY: -0.07, rotationSpeed: 0.5, startX: 0.2, startY: 0.7),
  _FloatingEmoji(emoji: '\u{2753}', size: 26, opacity: 0.15, speedX: -0.10, speedY: -0.04, rotationSpeed: -0.1, startX: 0.7, startY: 0.0),
  _FloatingEmoji(emoji: '\u{1F4E6}', size: 26, opacity: 0.13, speedX: 0.09, speedY: 0.05, rotationSpeed: 0.2, startX: 0.4, startY: 0.8),
  _FloatingEmoji(emoji: '\u{2B50}', size: 22, opacity: 0.25, speedX: -0.05, speedY: -0.06, rotationSpeed: -0.6, startX: 0.9, startY: 0.5),
  _FloatingEmoji(emoji: '\u{1F3A9}', size: 28, opacity: 0.12, speedX: 0.11, speedY: -0.02, rotationSpeed: 0.1, startX: 0.05, startY: 0.55),
  _FloatingEmoji(emoji: '\u{1F698}', size: 30, opacity: 0.14, speedX: -0.09, speedY: 0.07, rotationSpeed: -0.3, startX: 0.55, startY: 0.85),
  _FloatingEmoji(emoji: '\u{1F415}', size: 24, opacity: 0.11, speedX: 0.06, speedY: -0.08, rotationSpeed: 0.4, startX: 0.85, startY: 0.15),
  _FloatingEmoji(emoji: '\u{1F4B8}', size: 22, opacity: 0.20, speedX: -0.07, speedY: 0.09, rotationSpeed: -0.5, startX: 0.15, startY: 0.3),
  _FloatingEmoji(emoji: '\u{1F3B0}', size: 20, opacity: 0.18, speedX: 0.13, speedY: -0.04, rotationSpeed: 0.35, startX: 0.65, startY: 0.45),
  _FloatingEmoji(emoji: '\u{1F4B3}', size: 26, opacity: 0.16, speedX: -0.11, speedY: -0.05, rotationSpeed: -0.25, startX: 0.35, startY: 0.65),
  _FloatingEmoji(emoji: '\u{1F6F8}', size: 20, opacity: 0.12, speedX: 0.14, speedY: 0.03, rotationSpeed: 0.45, startX: 0.45, startY: 0.35),
  _FloatingEmoji(emoji: '\u{1F911}', size: 28, opacity: 0.17, speedX: -0.13, speedY: -0.03, rotationSpeed: -0.15, startX: 0.95, startY: 0.75),
  _FloatingEmoji(emoji: '\u{1F3AA}', size: 26, opacity: 0.10, speedX: 0.05, speedY: 0.10, rotationSpeed: 0.2, startX: 0.1, startY: 0.9),
  _FloatingEmoji(emoji: '\u{1F3AF}', size: 20, opacity: 0.19, speedX: -0.08, speedY: -0.07, rotationSpeed: -0.4, startX: 0.6, startY: 0.05),
  _FloatingEmoji(emoji: '\u{26F3}', size: 24, opacity: 0.11, speedX: 0.10, speedY: 0.04, rotationSpeed: 0.1, startX: 0.8, startY: 0.7),
  _FloatingEmoji(emoji: '\u{1F3C1}', size: 22, opacity: 0.16, speedX: -0.06, speedY: -0.10, rotationSpeed: -0.3, startX: 0.3, startY: 0.5),
];

class _MonopolyBackgroundPainter extends CustomPainter {
  final double animationValue;

  _MonopolyBackgroundPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = kBgDark;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    _drawGrid(canvas, size);
    _drawFloatingEmojis(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double gridOffset = animationValue * 120;
    const double gridSize = 80;

    for (double x = -gridSize + (gridOffset % gridSize); x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = -gridSize + (gridOffset % gridSize); y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawFloatingEmojis(Canvas canvas, Size size) {
    for (final e in _emojis) {
      final x = (_wrap(e.startX + animationValue * e.speedX) * size.width);
      final y = (_wrap(e.startY + animationValue * e.speedY) * size.height);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * e.rotationSpeed * math.pi * 2);

      final tp = TextPainter(
        text: TextSpan(
          text: e.emoji,
          style: TextStyle(
            fontSize: e.size,
            color: Colors.white.withValues(alpha: e.opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  double _wrap(double value) {
    final v = value % 1.4;
    if (v > 1.0) return v - 1.0;
    return v;
  }

  @override
  bool shouldRepaint(covariant _MonopolyBackgroundPainter oldDelegate) {
    return (oldDelegate.animationValue - animationValue).abs() > 0.001;
  }
}

class _HeaderWidget extends StatelessWidget {
  const _HeaderWidget();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPad = (width * 0.06).clamp(16.0, 32.0);
    final verticalPad = (width * 0.08).clamp(24.0, 40.0);
    final titleSize = (width * 0.12).clamp(28.0, 48.0);
    final titleSpacing = (width * 0.018).clamp(4.0, 10.0);
    final subtitleSize = (width * 0.035).clamp(12.0, 16.0);
    final subtitleSpacing = (width * 0.01).clamp(2.0, 6.0);
    final iconSize = (width * 0.08).clamp(24.0, 40.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: verticalPad, horizontal: horizontalPad),
          decoration: BoxDecoration(
            color: kBgDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: kGold.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -iconSize * 0.5,
                    right: -iconSize * 0.5,
                    child: Transform.rotate(
                      angle: 0.5,
                      child: Icon(Icons.payments_rounded, color: kGold.withValues(alpha: 0.15), size: iconSize),
                    ),
                  ),
                  Positioned(
                    bottom: -iconSize * 0.5,
                    left: -iconSize * 0.6,
                    child: Transform.rotate(
                      angle: -0.4,
                      child: Icon(Icons.currency_exchange_rounded, color: kGold.withValues(alpha: 0.1), size: iconSize * 0.9),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'MONOPOLY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: titleSpacing,
                        shadows: [
                          Shadow(color: Colors.white24, blurRadius: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'BANCA DIGITAL',
                style: TextStyle(
                  color: kTextSecondary,
                  fontSize: subtitleSize,
                  letterSpacing: subtitleSpacing,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
