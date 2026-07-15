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
import 'package:monopoly_banking/screens/onboarding_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final AnimationController _bgAnimCtrl;

  final AudioPlayer _musicPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _bgAnimCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
          ..repeat();
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
    String avatarId;
    String colorId;

    if (role == 'banco') {
      avatarId = '🏦';
      colorId = '4';
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

    // Cliente: onboarding (color → nombre → avatar)
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
    if (!mounted || result == null) return;

    final selectedColorIndex = result['colorIndex'] as int;
    final playerName = result['name'] as String;
    final avatarEmoji = result['avatarEmoji'] as String;

    avatarId = avatarEmoji;
    colorId = selectedColorIndex.toString();

    final session = context.read<SessionProvider>();
    try {
      await session.createSession(
        role: role,
        avatarId: avatarId,
        colorId: colorId,
        initialBalance: 0,
        name: playerName,
      );
    } catch (e, s) {
      if (mounted) context.showFriendlyError(e, s);
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmExitApp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Salir de la app?',
            style: TextStyle(color: kTextPrimary)),
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
            child:
                const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
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
                      animationValue: _bgAnimCtrl.value,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                          const SizedBox(height: 40),
                          AnimatedEntry(
                            delay: const Duration(milliseconds: 600),
                            child: _buildClientSection(),
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

class _RoleButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        onTap();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color,
                        color.withValues(alpha: 0.55),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
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
    );
  }
}

class _MonopolyBackgroundPainter extends CustomPainter {
  final double animationValue;

  _MonopolyBackgroundPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Fondo base oscuro
    final bgPaint = Paint()..color = kBgDark;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Dibujar cuadrículas/casillas de Monopoly moviéndose suavemente
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final double gridOffset =
        animationValue * 150; // desplazamiento total a lo largo de la animación
    const double gridSize = 80;

    for (double x = -gridSize + (gridOffset % gridSize);
        x < size.width;
        x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = -gridSize + (gridOffset % gridSize);
        y < size.height;
        y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Dibujar algunas figuras geométricas flotantes (billetes, casas) abstractas
    final shapePaint = Paint()
      ..color = kGold.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      final double x = (size.width * 0.2 * i +
              (animationValue * size.width * (i.isEven ? 0.3 : -0.2))) %
          size.width;
      final double y = (size.height * 0.3 * i +
              (animationValue * size.height * (i.isEven ? -0.2 : 0.4))) %
          size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * 2 * math.pi * (i.isEven ? 1 : -1));
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 40, height: 60),
          shapePaint);
      canvas.restore();
    }

    final housePaint = Paint()
      ..color = kGreenGlow.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final double x = (size.width * 0.25 * i +
              (animationValue * size.width * (i.isEven ? -0.4 : 0.3))) %
          size.width;
      final double y = (size.height * 0.25 * i +
              (animationValue * size.height * (i.isEven ? 0.3 : -0.3))) %
          size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(animationValue * 2 * math.pi * (i.isEven ? -1 : 1));

      // Forma de "casa" simple (cuadrado + triángulo invertido)
      final path = Path()
        ..moveTo(-15, 0) // techo izq
        ..lineTo(0, -15) // pico techo
        ..lineTo(15, 0) // techo der
        ..lineTo(15, 15) // pared der
        ..lineTo(-15, 15) // pared izq
        ..close();

      canvas.drawPath(path, housePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MonopolyBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
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
          padding: EdgeInsets.symmetric(
              vertical: verticalPad, horizontal: horizontalPad),
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
                      child: Icon(Icons.payments_rounded,
                          color: kGold.withValues(alpha: 0.15),
                          size: iconSize),
                    ),
                  ),
                  Positioned(
                    bottom: -iconSize * 0.5,
                    left: -iconSize * 0.6,
                    child: Transform.rotate(
                      angle: -0.4,
                      child: Icon(Icons.currency_exchange_rounded,
                          color: kGold.withValues(alpha: 0.1),
                          size: iconSize * 0.9),
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
