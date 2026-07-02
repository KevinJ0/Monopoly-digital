import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/screens/nfc_test_screen.dart';
import 'package:monopoly_banking/screens/ble_test_screen.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

const _avatars = ['🎩', '🚗', '🐶', '⚓', '🎸', '👢', '💰', '🛳️'];
const _colors = [
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFFFF7043),
  Color(0xFF00ACC1),
  Color(0xFFECEFF1),
];

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedAvatar = 0;
  int _selectedColor = 0;

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
    String? name;
    String avatarId;
    String colorId;

    if (role == 'banco') {
      avatarId = '💰';
      colorId = '4'; // Gold index
    } else {
      name = await _showNameDialog();
      if (!mounted) return;
      if (name == null || name.trim().isEmpty) return;
      name = name.trim();
      avatarId = _avatars[_selectedAvatar];
      colorId = _selectedColor.toString();
    }

    final session = context.read<SessionProvider>();
    try {
      await session.createSession(
        role: role,
        avatarId: avatarId,
        colorId: colorId,
        initialBalance: role == 'banco' ? double.infinity : 0,
        name: name,
      );
    } catch (e, s) {
      if (mounted) context.showFriendlyError(e, s);
      return;
    }
    if (mounted) setState(() {});
  }

  Future<String?> _showNameDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cómo te llamas?',
            style: TextStyle(color: kTextPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: kTextPrimary),
          decoration: InputDecoration(
            hintText: 'Tu nombre',
            hintStyle: TextStyle(color: kTextSecondary.withValues(alpha: 0.5)),
            filled: true,
            fillColor: kBgDark,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(ctx);
            },
            child:
                const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(ctx, controller.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _colors[_selectedColor],
              foregroundColor: _colors[_selectedColor].computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PlayerColorBackdrop(
        color: _colors[_selectedColor],
        child: Stack(
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
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.bluetooth_rounded,
                          color: kTextSecondary),
                      tooltip: 'BLE Debug',
                      onPressed: () {
                        SoundService.playClick();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const BleTestScreen()),
                        );
                      },
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.nfc_rounded, color: kTextSecondary),
                      tooltip: 'NFC Debug',
                      onPressed: () {
                        SoundService.playClick();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const NfcTestScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
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
                          const AnimatedEntry(
                            delay: Duration(milliseconds: 600),
                            child: _DividerWidget(),
                          ),
                          const SizedBox(height: 32),
                          AnimatedEntry(
                            delay: const Duration(milliseconds: 800),
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
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Elige tu ficha',
          style:
              TextStyle(color: kTextSecondary, fontSize: 13, letterSpacing: 1),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(_avatars.length, (i) {
            final selected = i == _selectedAvatar;
            return GestureDetector(
              onTap: () {
                SoundService.playClick();
                setState(() => _selectedAvatar = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: selected ? kGreenGlow : kBgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? kGreen : kBorder,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: kGreenGlow, blurRadius: 12)]
                      : null,
                ),
                child: Center(
                  child:
                      Text(_avatars[i], style: const TextStyle(fontSize: 28)),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Elige tu color',
          style:
              TextStyle(color: kTextSecondary, fontSize: 13, letterSpacing: 1),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_colors.length, (i) {
            final selected = i == _selectedColor;
            return GestureDetector(
              onTap: () {
                SoundService.playClick();
                setState(() => _selectedColor = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: _colors[i].withValues(alpha: 0.6),
                              blurRadius: 10)
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBankSection() {
    return Column(
      children: [
        _RoleButton(
          label: 'SER EL BANCO',
          subtitle: 'Control total de la partida',
          icon: Icons.account_balance_rounded,
          gradient: const LinearGradient(
              colors: [Color(0xFFB8860B), Color(0xFF8B4513)]),
          onTap: () => _pickRole('banco'),
        ),
      ],
    );
  }

  Widget _buildClientSection() {
    final color = _colors[_selectedColor];
    final bool isLight = color.computeLuminance() > 0.5;

    return Column(
      children: [
        _buildAvatarPicker(),
        const SizedBox(height: 28),
        _buildColorPicker(),
        const SizedBox(height: 32),
        _RoleButton(
          label: 'ENTRAR COMO CLIENTE',
          subtitle: 'Recibe capital al vincular con Banca',
          icon: Icons.person_rounded,
          gradient:
              LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
          foregroundColor: isLight ? Colors.black : Colors.white,
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
  final Gradient gradient;
  final VoidCallback onTap;
  final Color foregroundColor;

  const _RoleButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.foregroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: foregroundColor, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: foregroundColor.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
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
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Money flying decorations
            Positioned(
              top: -20,
              right: -30,
              child: Transform.rotate(
                angle: 0.5,
                child: Icon(Icons.payments_rounded,
                    color: Colors.white.withValues(alpha: 0.1), size: 40),
              ),
            ),
            Positioned(
              bottom: -15,
              left: -35,
              child: Transform.rotate(
                angle: -0.4,
                child: Icon(Icons.currency_exchange_rounded,
                    color: Colors.white.withValues(alpha: 0.08), size: 35),
              ),
            ),
            Positioned(
              top: 5,
              left: -50,
              child: Transform.rotate(
                angle: 0.2,
                child: Icon(Icons.payments_rounded,
                    color: Colors.white.withValues(alpha: 0.05), size: 45),
              ),
            ),
            const Text(
              'MONOPOLY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                shadows: [
                  Shadow(color: Colors.white24, blurRadius: 20),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'BANCA DIGITAL',
          style: TextStyle(
            color: kTextSecondary,
            fontSize: 14,
            letterSpacing: 4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                kGold.withValues(alpha: 0.5),
                Colors.transparent
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DividerWidget extends StatelessWidget {
  const _DividerWidget();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Container(height: 1, color: kBorder.withValues(alpha: 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'O TAMBIÉN',
            style: TextStyle(
                color: kTextSecondary.withValues(alpha: 0.5),
                fontSize: 10,
                letterSpacing: 2),
          ),
        ),
        Expanded(
            child: Container(height: 1, color: kBorder.withValues(alpha: 0.3))),
      ],
    );
  }
}
