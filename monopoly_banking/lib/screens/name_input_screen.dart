import 'dart:math';
import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';

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
  _NameSuggestion('🎩', 'Don Corleone', 'La mafia del dinero'),
  _NameSuggestion('🚗', 'Señor Ferrari', 'Velocidad pura'),
  _NameSuggestion('🐶', 'El Pug', 'Pequeño pero caro'),
  _NameSuggestion('⚓', 'La Ancla', 'Firme en la fortuna'),
  _NameSuggestion('🎸', 'El Maestro', 'Musico y banquero'),
  _NameSuggestion('👢', 'La Bota', 'Pisa fuerte el mercado'),
  _NameSuggestion('💰', 'Don Moneda', 'Cada centavo cuenta'),
  _NameSuggestion('🛳️', 'El Crucero', 'Viaje de lujo'),
  _NameSuggestion('🎩', 'El Sombrerero', 'Lleno de sorpresas'),
  _NameSuggestion('🚗', 'Señor Vroom', 'A toda velocidad'),
  _NameSuggestion('🐶', 'El Labrador', 'Busca tesoros'),
  _NameSuggestion('⚓', 'La Brújula', 'Siempre encuentra oro'),
  _NameSuggestion('🎸', 'El Metalero', 'Heavy metal y dinero'),
  _NameSuggestion('👢', 'El Botin', 'Botin de guerra'),
  _NameSuggestion('💰', 'La Tesorera', 'Guarda el oro'),
  _NameSuggestion('🛳️', 'El Pirata', 'Busca el tesoro'),
  _NameSuggestion('🎩', 'Don Magnifico', 'El mas elegante'),
  _NameSuggestion('🚗', 'Señor Drift', 'Derrapa hacia la victoria'),
  _NameSuggestion('🐶', 'El Caniche', 'Rico y caprichoso'),
  _NameSuggestion('⚓', 'El Puerto', 'Llegada segura'),
  _NameSuggestion('🎸', 'El Solista', 'Brilla solo'),
  _NameSuggestion('👢', 'La Botota', 'Pisa con estilo'),
  _NameSuggestion('💰', 'Don Fondo', 'Fondo infinito'),
  _NameSuggestion('🛳️', 'El Yate', 'Navega en oro'),
  _NameSuggestion('🎩', 'El Magician', 'Hace dinero desaparecer'),
  _NameSuggestion('🚗', 'Señor Nitro', 'Explosion de ganancias'),
  _NameSuggestion('🐶', 'El bulldog', 'Terco con el dinero'),
  _NameSuggestion('⚓', 'El Timonel', 'Dirige el barco'),
  _NameSuggestion('🎸', 'El Cantante', 'Canta por cash'),
  _NameSuggestion('👢', 'La Stiletto', 'Corta como navaja'),
  _NameSuggestion('💰', 'La Bolsa', 'Llena de acciones'),
  _NameSuggestion('🛳️', 'El Crucero', 'Turista de lujo'),
  _NameSuggestion('🎩', 'Don Trump', 'El deal maker'),
  _NameSuggestion('🚗', 'Señor Bugatti', 'Coche de ensueño'),
  _NameSuggestion('🐶', 'El Husky', 'Tiro con fuerza'),
  _NameSuggestion('⚓', 'El Ancla', 'Firme como roca'),
  _NameSuggestion('🎸', 'El DJ', 'Suena el cash'),
  _NameSuggestion('👢', 'La Chelsea', 'Estilo y dinero'),
  _NameSuggestion('💰', 'Don Billete', 'Siempre con efectivo'),
  _NameSuggestion('🛳️', 'El Gondola', 'Paseos romanticos'),
  _NameSuggestion('🎩', 'El Ilusionista', 'Multiplica el dinero'),
  _NameSuggestion('🚗', 'Señor Mustang', 'Libre y veloz'),
  _NameSuggestion('🐶', 'El golden', 'Dorado por naturaleza'),
  _NameSuggestion('⚓', 'El Lighthouse', 'Guia hacia el oro'),
  _NameSuggestion('🎸', 'El Baterista', 'Toca el ritmo del cash'),
  _NameSuggestion('👢', 'La Guara', 'Protege el tesoro'),
  _NameSuggestion('💰', 'La Caja', 'Guarda todo'),
  _NameSuggestion('🛳️', 'El Ferry', 'Transporta fortunas'),
  _NameSuggestion('🎩', 'Don Elegante', 'Impecable siempre'),
  _NameSuggestion('🚗', 'Señor Lamborghini', 'Caro y veloz'),
  _NameSuggestion('🐶', 'El Chihuahua', 'Pequeño pero audaz'),
  _NameSuggestion('⚓', 'El Compass', 'Siempre apunta al oro'),
  _NameSuggestion('🎸', 'El Pianista', 'Teclas de oro'),
  _NameSuggestion('👢', 'La Oxford', 'Clasico y elegante'),
  _NameSuggestion('💰', 'Don Tesoro', 'Caza tesoros'),
  _NameSuggestion('🛳️', 'El Speedboat', 'Rapido como el viento'),
  _NameSuggestion('🎩', 'El Baron', 'Baron de la fortuna'),
  _NameSuggestion('🚗', 'Señor Porsche', 'Aleman y preciso'),
  _NameSuggestion('🐶', 'El Beagle', 'Busca centavos'),
  _NameSuggestion('⚓', 'El Ancor', 'Nunca se mueve'),
  _NameSuggestion('🎸', 'El violinista', 'Melodia de oro'),
  _NameSuggestion('👢', 'La Sandalia', 'Pisa suave'),
  _NameSuggestion('💰', 'Don Tesoreria', ' Contador supremo'),
  _NameSuggestion('🛳️', 'El Submarino', 'Bajo el agua hay oro'),
  _NameSuggestion('🎩', 'El Presidente', 'Manda en el banco'),
  _NameSuggestion('🚗', 'Señor Tesla', 'Electrico y rapido'),
  _NameSuggestion('🐶', 'El Dalmata', '101 maneras de ganar'),
  _NameSuggestion('⚓', 'El Anclaje', 'Seguro y firme'),
  _NameSuggestion('🎸', 'El Saxofonista', 'Suena jazz y cash'),
  _NameSuggestion('👢', 'La Mocasin', 'Comodo y caro'),
  _NameSuggestion('💰', 'La Fortuna', 'Nace con oro'),
  _NameSuggestion('🛳️', 'El Catamaran', 'Doble hull, doble cash'),
  _NameSuggestion('🎩', 'El Counts', 'Conde de la plata'),
  _NameSuggestion('🚗', 'Señor McLaren', 'Precision britanica'),
  _NameSuggestion('🐶', 'El Boxer', 'Pelea por el dinero'),
  _NameSuggestion('⚓', 'El Nautico', 'Vida marina'),
  _NameSuggestion('🎸', 'El Flautista', 'Toca y cobra'),
  _NameSuggestion('👢', 'La Mora', 'Dulce y cara'),
  _NameSuggestion('💰', 'Don Centavo', 'Cada moneda importa'),
  _NameSuggestion('🛳️', 'El Velero', 'Viento a favor'),
  _NameSuggestion('🎩', 'El Caballero', 'Noble y rico'),
  _NameSuggestion('🚗', 'Señor Aston', 'Martin y dinero'),
  _NameSuggestion('🐶', 'El Pastor', 'Guarda el oro'),
  _NameSuggestion('⚓', 'El Faro', 'Ilumina el camino'),
  _NameSuggestion('🎸', 'El Arpista', 'Cuerdas de oro'),
  _NameSuggestion('👢', 'La Loafer', 'Sin prisa pero sin pausa'),
  _NameSuggestion('💰', 'Don Capital', 'Capital infinito'),
  _NameSuggestion('🛳️', 'El MegaYate', 'Super lujoso'),
  _NameSuggestion('🎩', 'El Senador', 'Leyes y dinero'),
  _NameSuggestion('🚗', 'Señor Bentley', 'Elegancia pura'),
  _NameSuggestion('🐶', 'El Schnauzer', 'Pelo y fortuna'),
  _NameSuggestion('⚓', 'El Veleiro', 'Libre como el viento'),
  _NameSuggestion('🎸', 'El Acordeonista', 'Acordeon de cash'),
  _NameSuggestion('👢', 'La Platform', 'Siempre arriba'),
  _NameSuggestion('💰', 'La Cuentista', 'Cuenta cada centavo'),
  _NameSuggestion('🛳️', 'El Trimaran', 'Triple velocidad'),
  _NameSuggestion('🎩', 'El Alcalde', 'Ciudad de oro'),
  _NameSuggestion('🚗', 'Señor Rolls', 'Royce de la fortuna'),
  _NameSuggestion('🐶', 'El Terrier', 'Pequeño luchador'),
  _NameSuggestion('⚓', 'El Navegante', 'Busca nouvelles tierras'),
  _NameSuggestion('🎸', 'El DJ Cash', 'Suena el dinero'),
  _NameSuggestion('👢', 'La Derby', 'Clasico ganador'),
  _NameSuggestion('💰', 'Don Banco', 'El banco ambulante'),
  _NameSuggestion('🛳️', 'El MegaCrucero', 'Ciudad flotante'),
  _NameSuggestion('🎩', 'El Principe', 'Heredero del trono'),
  _NameSuggestion('🚗', 'Señor Maserati', 'Italiano y caro'),
  _NameSuggestion('🐶', 'El Pomerania', 'Furioso y rico'),
  _NameSuggestion('⚓', 'El Remo', 'Rema hacia la fortuna'),
  _NameSuggestion('🎸', 'El Trompetista', 'Trompeta de oro'),
  _NameSuggestion('👢', 'La Oxford', 'Classico y elegante'),
  _NameSuggestion('💰', 'Don Interes', 'Los intereses hablan'),
  _NameSuggestion('🛳️', 'El Buque', 'Grande y poderoso'),
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
