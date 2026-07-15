import 'dart:math';
import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';

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

const _colorLabels = {
  0: 'Rojo',
  1: 'Morado',
  2: 'Azul',
  3: 'Verde',
  4: 'Dorado',
  5: 'Naranja',
  6: 'Turquesa',
  7: 'Plata',
  8: 'Marrón',
  9: 'Azul Claro',
  10: 'Rosa',
  11: 'Naranja Claro',
  12: 'Rojo Claro',
  13: 'Amarillo',
  14: 'Verde Claro',
  15: 'Azul Oscuro',
};

const _avatars = [
  '🎩', '🚗', '🐶', '⚓', '🎸', '👢', '💰', '🛳️',
  '🐱', '👑', '💎', '🤖', '👽', '🧙', '🔥', '⭐',
  '🎲', '🎯', '🏆', '🦄', '🐉', '🃏', '🦅', '🦈',
];

const _avatarLabels = {
  '🎩': 'Sombrero', '🚗': 'Auto', '🐶': 'Perro', '⚓': 'Ancla',
  '🎸': 'Guitarra', '👢': 'Bota', '💰': 'Dinero', '🛳️': 'Yate',
  '🐱': 'Gato', '👑': 'Corona', '💎': 'Diamante', '🤖': 'Robot',
  '👽': 'Alien', '🧙': 'Mago', '🔥': 'Fuego', '⭐': 'Estrella',
  '🎲': 'Dados', '🎯': 'Diana', '🏆': 'Trofeo', '🦄': 'Unicornio',
  '🐉': 'Dragon', '🃏': 'Comodin', '🦅': 'Aguila', '🦈': 'Tiburon',
};

class _NameSuggestion {
  final String emoji;
  final String label;
  final String subtitle;
  const _NameSuggestion(this.emoji, this.label, this.subtitle);
}

const _allSuggestions = [
  _NameSuggestion('🎩', 'Don Billetes', 'El rey del efectivo'),
  _NameSuggestion('🚗', 'Señor Turbo', 'Conduce rapido, paga despues'),
  _NameSuggestion('🐶', 'Capitan Kuarto', 'Siempre quiebra'),
  _NameSuggestion('⚓', 'Almirante Oro', 'Navega en yates'),
  _NameSuggestion('🎸', 'El Roquero', 'Dinero o muerte'),
  _NameSuggestion('👢', 'La Estafadora', 'Nunca paga impuestos'),
  _NameSuggestion('💰', 'Señor Impuestos', 'Cobra por respirar'),
  _NameSuggestion('🛳️', 'Capitan Casino', 'Todo o nada'),
  _NameSuggestion('🎩', 'Don Dinero', 'El banquero mas rico'),
  _NameSuggestion('🚗', 'La Ferrari', 'Velocidad y poder'),
  _NameSuggestion('🐶', 'El Firulais', 'Mascota millonaria'),
  _NameSuggestion('⚓', 'Capitan Barco', 'Ancorado en la fortuna'),
  _NameSuggestion('🎸', 'El Guitarrista', 'Rock y roll finance'),
  _NameSuggestion('👢', 'La vaquera', 'Domaselos billetes'),
  _NameSuggestion('💰', 'Señor Pesos', 'Lleno de billetes'),
  _NameSuggestion('🛳️', 'La Yate', 'Crucero de lujo'),
  _NameSuggestion('🎩', 'El Duende', 'Mago del dinero'),
  _NameSuggestion('🚗', 'Señor Carrera', 'Meta: ser millonario'),
  _NameSuggestion('🐶', 'La Perrita', 'Dulce pero cara'),
  _NameSuggestion('⚓', 'El Marinero', 'Navega sin rumbo'),
  _NameSuggestion('🎸', 'El Virtuoso', 'Toca la fortuna'),
  _NameSuggestion('👢', 'El Vaquero', 'Domando billetes'),
  _NameSuggestion('💰', 'La Abuela', 'Ahorra para el funeral'),
  _NameSuggestion('🛳️', 'El Capitan', 'Mando absoluto'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;

  int _selectedColorIndex = Random().nextInt(_palette.length);
  String _playerName = '';
  int _selectedAvatarIndex = 0;

  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _nameFormKey = GlobalKey<FormState>();
  int? _selectedSuggestion;
  late final List<_NameSuggestion> _visibleSuggestions;

  Color get _accent => _palette[_selectedColorIndex];

  int get _totalPages => 3;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    final rng = Random();
    _visibleSuggestions = List.from(_allSuggestions)..shuffle(rng);
    _visibleSuggestions.removeRange(24, _visibleSuggestions.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _goToNext() {
    FocusScope.of(context).unfocus();
    if (_currentPage < _totalPages - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPrevious() {
    FocusScope.of(context).unfocus();
    if (_currentPage > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onColorContinue() {
    SoundService.playClick();
    _goToNext();
  }

  void _onNameContinue() {
    final isValid = _nameFormKey.currentState?.validate() ?? false;
    if (!isValid) return;
    SoundService.playClick();
    _playerName = _nameController.text.trim();
    final idx = _selectedSuggestion;
    if (idx != null) {
      _finish(avatarEmoji: _visibleSuggestions[idx].emoji, avatarIndex: idx);
    } else {
      _goToNext();
    }
  }

  void _onAvatarContinue() {
    SoundService.playClick();
    _finish(
      avatarEmoji: _avatars[_selectedAvatarIndex],
      avatarIndex: _selectedAvatarIndex,
    );
  }

  void _finish({required String avatarEmoji, required int avatarIndex}) {
    Navigator.of(context).pop({
      'colorIndex': _selectedColorIndex,
      'name': _playerName,
      'avatarEmoji': avatarEmoji,
      'avatarIndex': avatarIndex,
    });
  }

  void _selectSuggestion(int index) {
    SoundService.playClick();
    _nameFocusNode.unfocus();
    setState(() {
      _selectedSuggestion = index;
      _playerName = _visibleSuggestions[index].label;
      _nameController.text = _playerName;
    });
    _onNameContinue();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToPrevious();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        color: _accent.withValues(alpha: 0.08),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: kTextSecondary, size: 20),
              onPressed: () {
                SoundService.playClick();
                _goToPrevious();
              },
            ),
            title: Text(
              _currentPage == 0
                  ? 'Elige tu color'
                  : _currentPage == 1
                      ? 'Crea tu perfil'
                      : 'Elige tu icono',
              style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              if (_currentPage < 2)
                TextButton(
                  onPressed: _currentPage == 0
                      ? _onColorContinue
                      : _onNameContinue,
                  child: Text(
                    'Continuar',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: _onAvatarContinue,
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: List.generate(_totalPages, (i) {
                    final active = i == _currentPage;
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 3,
                        decoration: BoxDecoration(
                          color: active
                              ? _accent
                              : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          body: Stack(
            children: [
              const Positioned.fill(
                child: MonopolyBackground(child: SizedBox.expand()),
              ),
              Positioned.fill(
                child: _DynamicColorBackdrop(color: _accent),
              ),
              PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildColorPage(),
                  _buildNamePage(),
                  _buildAvatarPage(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorPage() {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          final isShort = constraints.maxHeight < 700;
          final hPad = isWide ? 32.0 : 20.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    AnimatedEntry(
                      delay: const Duration(milliseconds: 200),
                      child: _buildColorLabel(),
                    ),
                    SizedBox(height: isShort ? 10 : 16),
                    AnimatedEntry(
                      delay: const Duration(milliseconds: 300),
                      child: _buildColorGrid(isWide, isShort),
                    ),
                    SizedBox(height: isShort ? 20 : 32),
                    AnimatedEntry(
                      delay: const Duration(milliseconds: 400),
                      child: _buildPreviewCard(isShort),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNamePage() {
    return PlayerColorBackdrop(
      color: _accent,
      child: SafeArea(
        top: false,
        child: Form(
          key: _nameFormKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              final hPad = isWide ? 32.0 : 20.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 100),
                          child: _NameTitleSection(accent: _accent),
                        ),
                        const SizedBox(height: 20),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 200),
                          child: _buildTextField(),
                        ),
                        const SizedBox(height: 28),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 300),
                          child: _buildSuggestionsHeader(),
                        ),
                        const SizedBox(height: 12),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 350),
                          child: _buildSuggestionsGrid(isWide),
                        ),
                      ],
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

  Widget _buildAvatarPage() {
    return PlayerColorBackdrop(
      color: _accent,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final hPad = isWide ? 32.0 : 20.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      AnimatedEntry(
                        delay: const Duration(milliseconds: 100),
                        child: _buildAvatarPreview(),
                      ),
                      const SizedBox(height: 28),
                      AnimatedEntry(
                        delay: const Duration(milliseconds: 200),
                        child: _buildAvatarLabel(),
                      ),
                      const SizedBox(height: 16),
                      AnimatedEntry(
                        delay: const Duration(milliseconds: 300),
                        child: _buildAvatarGrid(isWide),
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
    );
  }

  // ─── Color page widgets ───

  Widget _buildColorLabel() {
    final label = _colorLabels[_selectedColorIndex] ?? '';
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
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Color: $label',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorGrid(bool isWide, bool isShort) {
    final crossAxisCount = isWide ? 8 : 4;
    final spacing = isShort ? 8.0 : 14.0;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: _palette.length,
      itemBuilder: (context, index) => _buildColorCircle(index),
    );
  }

  Widget _buildColorCircle(int index) {
    final color = _palette[index];
    final selected = _selectedColorIndex == index;
    final isLight = color.computeLuminance() > 0.5;
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        setState(() => _selectedColorIndex = index);
      },
      child: FractionallySizedBox(
        widthFactor: 0.7,
        heightFactor: 0.7,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 14,
                      spreadRadius: 3,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: isLight ? Colors.black : Colors.white,
                  size: 26,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildPreviewCard(bool isShort) {
    final cardHeight = isShort ? 190.0 : 240.0;
    final vPad = isShort ? 16.0 : 24.0;
    final balanceSize = isShort ? 18.0 : 22.0;
    final textColor = _accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Container(
      width: double.infinity,
      height: cardHeight,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent,
            _accent.withValues(alpha: 0.7),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Icon(Icons.circle,
                size: 200, color: Colors.white.withValues(alpha: 0.1)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 100,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(vPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 26,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFFF5E6A3)],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 16,
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.black26, width: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Text('MONOPOLY',
                        style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '•••• •••• •••• ••••',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.6),
                      fontSize: 18,
                      letterSpacing: 4,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('JUGADOR',
                              style: TextStyle(
                                  color: textColor.withValues(alpha: 0.54), fontSize: 8)),
                          Text('TU NOMBRE',
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('SALDO',
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.54), fontSize: 8)),
                        Text('\$2,000',
                            style: TextStyle(
                              color: textColor,
                              fontSize: balanceSize,
                              fontWeight: FontWeight.w900,
                            )),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Name page widgets ───

  Widget _buildTextField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TU NOMBRE',
          style: TextStyle(
            color: kTextSecondary,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _onNameContinue(),
          decoration: InputDecoration(
            hintText: 'Escribe tu nombre',
            hintStyle: TextStyle(
              color: kTextSecondary.withValues(alpha: 0.4),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon:
                Icon(Icons.person_rounded, color: _accent, size: 22),
            filled: true,
            fillColor: kBgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _accent, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kRed),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kRed, width: 1.5),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Ingresa tu nombre';
            if (v.trim().length < 2) return 'Minimo 2 caracteres';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSuggestionsHeader() {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: kGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'O ELIGE UN NOMBRE',
          style: TextStyle(
            color: kTextSecondary.withValues(alpha: 0.7),
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionsGrid(bool isWide) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 2 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: isWide ? 3.0 : 2.6,
      ),
      itemCount: _visibleSuggestions.length,
      itemBuilder: (context, index) => _buildSuggestionTile(index),
    );
  }

  Widget _buildSuggestionTile(int index) {
    final s = _visibleSuggestions[index];
    final selected = _selectedSuggestion == index;
    return GestureDetector(
      onTap: () => _selectSuggestion(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.12) : kBgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _accent : kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kBgDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child:
                      Text(s.emoji, style: const TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _accent : kTextPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kTextSecondary.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: _accent, size: 18),
          ],
        ),
      ),
    );
  }

  // ─── Avatar page widgets ───

  Widget _buildAvatarPreview() {
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
              _avatars[_selectedAvatarIndex],
              style: const TextStyle(fontSize: 42),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _playerName,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarLabel() {
    final label = _avatarLabels[_avatars[_selectedAvatarIndex]] ?? '';
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
          Text(_avatars[_selectedAvatarIndex],
              style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const Text('Icono:',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildAvatarGrid(bool isWide) {
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
    final selected = _selectedAvatarIndex == index;
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        setState(() => _selectedAvatarIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.2) : kBgCard,
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
          child: Text(emoji, style: TextStyle(fontSize: selected ? 28 : 24)),
        ),
      ),
    );
  }
}

class _NameTitleSection extends StatelessWidget {
  final Color accent;
  const _NameTitleSection({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.person_add_rounded, color: accent, size: 28),
            const SizedBox(width: 10),
            Text(
              'Crea tu perfil',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Escribe tu nombre o elige uno de la lista',
          style: TextStyle(
            color: kTextSecondary.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _DynamicColorBackdrop extends StatelessWidget {
  final Color color;
  const _DynamicColorBackdrop({required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.2,
          colors: [
            color.withValues(alpha: 0.08),
            kBgDark,
          ],
        ),
      ),
    );
  }
}
