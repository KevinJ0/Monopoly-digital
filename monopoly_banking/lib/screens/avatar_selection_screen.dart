import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';

const _avatars = [
  '🎩',
  '🚗',
  '🐶',
  '⚓',
  '🎸',
  '👢',
  '💰',
  '🛳️',
  '🐱',
  '👑',
  '💎',
  '🤖',
  '👽',
  '🧙',
  '🔥',
  '⭐',
  '🎲',
  '🎯',
  '🏆',
  '🦄',
  '🐉',
  '🃏',
  '🦅',
  '🦈',
];

const _avatarLabels = {
  '🎩': 'Sombrero',
  '🚗': 'Auto',
  '🐶': 'Perro',
  '⚓': 'Ancla',
  '🎸': 'Guitarra',
  '👢': 'Bota',
  '💰': 'Dinero',
  '🛳️': 'Yate',
  '🐱': 'Gato',
  '👑': 'Corona',
  '💎': 'Diamante',
  '🤖': 'Robot',
  '👽': 'Alien',
  '🧙': 'Mago',
  '🔥': 'Fuego',
  '⭐': 'Estrella',
  '🎲': 'Dados',
  '🎯': 'Diana',
  '🏆': 'Trofeo',
  '🦄': 'Unicornio',
  '🐉': 'Dragon',
  '🃏': 'Comodin',
  '🦅': 'Aguila',
  '🦈': 'Tiburon',
};

const _palette = [
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

class AvatarSelectionScreen extends StatefulWidget {
  final int colorIndex;
  final String playerName;
  const AvatarSelectionScreen({
    super.key,
    required this.colorIndex,
    required this.playerName,
  });

  @override
  State<AvatarSelectionScreen> createState() =>
      _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  late final AnimationController _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

  Color get _accent => _palette[widget.colorIndex];

  @override
  void initState() {
    super.initState();
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    SoundService.playClick();
    Navigator.of(context).pop({
      'avatarEmoji': _avatars[_selectedIndex],
      'avatarIndex': _selectedIndex,
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: kBgDark,
        appBar: AppBar(
          backgroundColor: kBgDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: kTextSecondary, size: 20),
            onPressed: () {
              SoundService.playClick();
              Navigator.of(context).pop();
            },
          ),
          title: const Text('Elige tu icono',
              style: TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: _onContinue,
              child: Text(
                'Continuar',
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        body: MonopolyBackground(
          child: PlayerColorBackdrop(
            color: _accent,
            child: FadeTransition(
              opacity: _fade,
              child: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    final hPad = isWide ? 32.0 : 20.0;
                    return SingleChildScrollView(
                      padding:
                          EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 600),
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              AnimatedEntry(
                                delay: const Duration(
                                    milliseconds: 100),
                                child: _buildPreview(),
                              ),
                              const SizedBox(height: 28),
                              AnimatedEntry(
                                delay: const Duration(
                                    milliseconds: 200),
                                child: _buildLabel(),
                              ),
                              const SizedBox(height: 16),
                              AnimatedEntry(
                                delay: const Duration(
                                    milliseconds: 300),
                                child: _buildGrid(isWide),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accent.withValues(alpha: 0.2),
            border: Border.all(color: _accent, width: 3),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              _avatars[_selectedIndex],
              style: const TextStyle(fontSize: 42),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.playerName,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel() {
    final label = _avatarLabels[_avatars[_selectedIndex]] ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _avatars[_selectedIndex],
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          const Text(
            'Icono:',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(bool isWide) {
    final crossAxisCount = isWide ? 8 : 6;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _avatars.length,
      itemBuilder: (context, index) => _buildAvatarCircle(index),
    );
  }

  Widget _buildAvatarCircle(int index) {
    final emoji = _avatars[index];
    final selected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        setState(() => _selectedIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color:
              selected ? _accent.withValues(alpha: 0.2) : kBgCard,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _accent : kBorder,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(
              fontSize: selected ? 28 : 24,
            ),
          ),
        ),
      ),
    );
  }
}
