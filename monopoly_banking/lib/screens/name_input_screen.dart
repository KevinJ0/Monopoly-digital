import 'dart:math';
import 'package:flutter/material.dart';
import 'package:money_manager/core/constants.dart';
import 'package:money_manager/services/sound_service.dart';
import 'package:money_manager/widgets/animated_entry.dart';
import 'package:money_manager/widgets/money_manager_background.dart';
import 'package:money_manager/widgets/player_color_backdrop.dart';

class _NameSuggestion {
  final String emoji;
  final String label;
  final String subtitle;
  const _NameSuggestion(this.emoji, this.label, this.subtitle);
}

// Bank-provided name suggestions for new players
// These are the official name options approved by the central bank
// Each suggestion is curated by the bank to maintain consistency across the network
const _allSuggestions = [
  _NameSuggestion('🏦', 'Don Billetes', 'El rey del efectivo'),
  _NameSuggestion('🏦', 'Don Dinero', 'El banquero mas rico'),
  _NameSuggestion('🏦', 'El Duende', 'Mago del dinero'),
  _NameSuggestion('🏦', 'El Sombrerero', 'Lleno de sorpresas'),
  _NameSuggestion('🏦', 'El Magician', 'Hace dinero desaparecer'),
  _NameSuggestion('🏦', 'Don Trump', 'El deal maker'),
  _NameSuggestion('🏦', 'El Ilusionista', 'Multiplica el dinero'),
  _NameSuggestion('🏦', 'Don Elegante', 'Impecable siempre'),
  _NameSuggestion('🏦', 'El Baron', 'Baron de la fortuna'),
  _NameSuggestion('🏦', 'El Senador', 'Leyes y dinero'),
  _NameSuggestion('🏦', 'El Alcalde', 'Ciudad de oro'),
  _NameSuggestion('🏦', 'El Principe', 'Heredero del trono'),
  _NameSuggestion('🏦', 'Don Corleone', 'La mafia del dinero'),
  _NameSuggestion('🏦', 'Don Magnifico', 'El mas elegante'),
  _NameSuggestion('🏦', 'El Magisterio', 'Señor de las finanzas'),
  _NameSuggestion('🏦', 'El Financiero', ' Maestro del dinero'),
  _NameSuggestion('🏦', 'El Banquero', 'Arquitecto de la fortuna'),
  _NameSuggestion('🏦', 'El Creador', 'Hacedor de multimillonarios'),
  _NameSuggestion('🏦', 'El Infalible', 'Nunca pierde'),
  _NameSuggestion('🏦', 'El Inversor', 'Maestro de las inversiones'),
  _NameSuggestion('🏦', 'El Administrador', 'Gestor del patrimonio'),
  _NameSuggestion('🏦', 'El Mercader', 'Negocios y ganancias'),
  _NameSuggestion('🏦', 'El Culminador', 'Alcanza el éxito'),
  _NameSuggestion('🏦', 'El Magnate', 'Grande y poderoso'),
  _NameSuggestion('🏦', 'El Rey', 'Monarca del efectivo'),
  _NameSuggestion('🏦', 'El Jefe', 'Jefe supremo de las finanzas'),
  _NameSuggestion('🏦', 'El Señor', 'Señor del dinero'),
  _NameSuggestion('🏦', 'El Gran', 'El mas grande banquero'),
  _NameSuggestion('🏦', 'El Poderoso', 'Dueño del capital'),
  _NameSuggestion('🏦', 'El Prodigo', 'Gasta con estilo'),
  _NameSuggestion('🏦', 'El Sabio', 'Consejero financiero'),
  _NameSuggestion('🏦', 'El Experto', 'Maestro del mercado'),
  _NameSuggestion('🏦', 'El Legendario', 'Mito del negocio'),
  _NameSuggestion('🏦', 'El Histórico', 'Grandes logros'),
  _NameSuggestion('🏦', 'El Imperial', 'Monarquía financiera'),
  _NameSuggestion('🏦', 'El Patriarca', 'Anciano de las finanzas'),
  _NameSuggestion('🏦', 'El Mentor', 'Guía a los ricos'),
  _NameSuggestion('🏦', 'El Victorioso', 'Siempre gana'),
  _NameSuggestion('🏦', 'El Astuto', 'Juega inteligente'),
  _NameSuggestion('🏦', 'El Brillante', 'Resplandor del efectivo'),
  _NameSuggestion('🏦', 'El Splendid', 'Elegante banquero'),
  _NameSuggestion('🏦', 'El Espléndido', 'Luz de las finanzas'),
];

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

class NameInputScreen extends StatefulWidget {
  final int colorIndex;
  const NameInputScreen({super.key, required this.colorIndex});

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  int? _selectedSuggestion;
  late final List<_NameSuggestion> _visibleSuggestions;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  Color get _accent => _palette[widget.colorIndex];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    final rng = Random();
    _visibleSuggestions = List.from(_allSuggestions)..shuffle(rng);
    _visibleSuggestions.removeRange(24, _visibleSuggestions.length);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _selectSuggestion(int index) {
    SoundService.playClick();
    _focusNode.unfocus();
    setState(() {
      _selectedSuggestion = index;
      _controller.text = _visibleSuggestions[index].label;
    });
    _onContinue();
  }

  void _onContinue() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    SoundService.playClick();
    final name = _controller.text.trim();
    final idx = _selectedSuggestion;
    if (idx != null) {
      Navigator.of(context).pop({
        'name': name,
        'avatarIndex': idx,
        'avatarEmoji': _visibleSuggestions[idx].emoji,
      });
    } else {
      Navigator.of(context).pop({
        'name': name,
        'avatarIndex': -1,
        'avatarEmoji': '',
      });
    }
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
          title: const Text('Crea tu perfil',
              style: TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          centerTitle: true,
          actions: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final valid = _controller.text.trim().length >= 2;
                return TextButton(
                  onPressed: valid ? _onContinue : null,
                  child: Text(
                    'Continuar',
                    style: TextStyle(
                      color: valid ? _accent : kTextSecondary.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: MoneyManagerBackground(
          child: PlayerColorBackdrop(
            color: _accent,
            child: FadeTransition(
              opacity: _fade,
              child: SafeArea(
                top: false,
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      final hPad = isWide ? 32.0 : 20.0;
                      return SingleChildScrollView(
                        padding:
                            EdgeInsets.fromLTRB(hPad, 8, hPad, 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 600),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                AnimatedEntry(
                                  delay:
                                      const Duration(milliseconds: 100),
                                  child: _TitleSection(accent: _accent),
                                ),
                                const SizedBox(height: 20),
                                AnimatedEntry(
                                  delay: const Duration(
                                      milliseconds: 200),
                                  child: _buildTextField(),
                                ),
                                const SizedBox(height: 28),
                                AnimatedEntry(
                                  delay: const Duration(
                                      milliseconds: 300),
                                  child:
                                      _buildSuggestionsHeader(),
                                ),
                                const SizedBox(height: 12),
                                AnimatedEntry(
                                  delay: const Duration(
                                      milliseconds: 350),
                                  child: _buildSuggestionsGrid(
                                      isWide),
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
            ),
          ),
        ),
      ),
    );
  }

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
          controller: _controller,
          focusNode: _focusNode,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _onContinue(),
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
}

class _TitleSection extends StatelessWidget {
  final Color accent;
  const _TitleSection({required this.accent});

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

