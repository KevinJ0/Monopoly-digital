import 'dart:math';
import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';

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

class ColorSelectionScreen extends StatefulWidget {
  const ColorSelectionScreen({super.key});

  @override
  State<ColorSelectionScreen> createState() => _ColorSelectionScreenState();
}

class _ColorSelectionScreenState extends State<ColorSelectionScreen> {
  int _selectedColorIndex = Random().nextInt(_palette.length);

  Color get _selectedColor => _palette[_selectedColorIndex];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        color: _selectedColor.withValues(alpha: 0.08),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: kTextSecondary, size: 20),
              onPressed: () {
                SoundService.playClick();
                Navigator.of(context).pop();
              },
            ),
            title: const Text('Elige tu color',
                style: TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: () {
                  SoundService.playClick();
                  Navigator.of(context).pop({
                    'colorIndex': _selectedColorIndex,
                    'color': _selectedColor,
                  });
                },
                child: Text(
                  'Continuar',
                  style: TextStyle(
                    color: _selectedColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              const Positioned.fill(
                child: MonopolyBackground(child: SizedBox.expand()),
              ),
              Positioned.fill(
                child: _DynamicColorBackdrop(color: _selectedColor),
              ),
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
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

  Widget _buildColorLabel() {
    final label = _colorLabels[_selectedColorIndex] ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _selectedColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _selectedColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _selectedColor,
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
    );
  }

  Widget _buildPreviewCard(bool isShort) {
    final cardHeight = isShort ? 150.0 : 200.0;
    final vPad = isShort ? 16.0 : 24.0;
    final balanceSize = isShort ? 18.0 : 22.0;
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
            _selectedColor,
            _selectedColor.withValues(alpha: 0.7),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _selectedColor.withValues(alpha: 0.3),
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
                            border: Border.all(
                                color: Colors.black26, width: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const Text('MONOPOLY',
                        style: TextStyle(
                            color: Colors.white70,
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
                      color: Colors.white.withValues(alpha: 0.6),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('JUGADOR',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 8)),
                          Text('TU NOMBRE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('SALDO',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 8)),
                        Text('\$2,000',
                            style: TextStyle(
                              color: Colors.white,
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
