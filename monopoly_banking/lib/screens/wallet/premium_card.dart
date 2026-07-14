part of '../wallet_screen.dart';

class _PremiumCreditCard extends StatefulWidget {
  final double balance;
  final String name;
  final Color color;
  final int colorId;
  final List<double> history;
  final bool isBank;
  final CardTier? tier;

  const _PremiumCreditCard({
    required this.balance,
    required this.name,
    required this.color,
    required this.colorId,
    required this.history,
    required this.isBank,
    this.tier,
  });

  @override
  State<_PremiumCreditCard> createState() => _PremiumCreditCardState();
}

class _PremiumCreditCardState extends State<_PremiumCreditCard> {
  static const double _tiltFactor = 24.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double get balance => widget.balance;
  String get name => widget.name;
  Color get color => widget.color;
  int get colorId => widget.colorId;
  List<double> get history => widget.history;
  bool get isBank => widget.isBank;

  @override
  void initState() {
    super.initState();
    try {
      _gyroSub = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen((event) {
        if (!mounted) return;
        setState(() {
          _gyroX = (event.y).clamp(-0.8, 0.8);
          _gyroY = (-event.x).clamp(-0.8, 0.8);
        });
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cardHeight =
          ((constraints.maxWidth - 32) / 1.586).clamp(0.0, 240.0);

      final nameLower = widget.name.toLowerCase().trim();
      final Widget cardContent;
      if (nameLower == 'kevin' || nameLower == 'meibi') {
        cardContent = _buildVipBlackCard(cardHeight: cardHeight);
      } else {
        final wallet = context.read<WalletController>();
        final tier = widget.tier ?? wallet.currentTier;
        final styles = _getStyles(tier, color);

        cardContent = switch (tier) {
          CardTier.standard =>
            _buildStandardCard(styles, cardHeight: cardHeight),
          CardTier.gold => _buildGoldCard(styles, cardHeight: cardHeight),
          CardTier.platinum =>
            _buildPlatinumCard(styles, cardHeight: cardHeight),
          CardTier.black => _buildBlackCard(styles, cardHeight: cardHeight),
        };
      }

      return Transform(
        alignment: FractionalOffset.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_gyroY / _tiltFactor)
          ..rotateY(_gyroX / _tiltFactor),
        child: _ShimmerCard(child: cardContent),
      );
    });
  }

  Widget _buildStandardCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: styles.gradient,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
              color: styles.accent.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 8),
              spreadRadius: 0),
          BoxShadow(
              color: styles.accent.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
              right: -30,
              top: -30,
              child: Icon(Icons.circle, size: 200, color: Colors.white10)),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: cardHeight * 0.5,
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Text(styles.tierName,
                        style: const TextStyle(
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
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 4,
                          fontFamily: 'Courier')),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('JUGADOR',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 8)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('SALDO',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 8)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OdometerWidget(
                                  value: balance,
                                  color: Colors.white,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                              const SizedBox(width: 8),
                              _buildCardNetworkLogo(isVisa: true),
                            ],
                          ),
                        ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldCard(_CardStyles styles, {required double cardHeight}) {
    const goldLight = Color(0xFFFCF6BA);
    const goldDeep = Color(0xFFBF953F);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: styles.gradient,
        border: Border.all(
          color: goldLight.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
              color: goldDeep.withValues(alpha: 0.25),
              blurRadius: 14,
              spreadRadius: 0,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: goldLight.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Center(
              child: Opacity(
                  opacity: 0.1,
                  child:
                      Icon(Icons.stars_rounded, size: 200, color: goldLight))),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: cardHeight * 0.5,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16)),
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Text(styles.tierName,
                        style: TextStyle(
                            color: goldLight.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFF3E2723),
                          fontSize: 18,
                          letterSpacing: 4,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('GOLD MEMBER',
                                style: TextStyle(
                                    color: Color(0xFF5D4037),
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFF3E2723),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('SALDO DISPONIBLE',
                              style: TextStyle(
                                  color: Color(0xFF5D4037),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OdometerWidget(
                                  value: balance,
                                  color: const Color(0xFF3E2723),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF3E2723))),
                              const SizedBox(width: 8),
                              _buildCardNetworkLogo(isVisa: false),
                            ],
                          ),
                        ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatinumCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: styles.gradient,
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(
        children: [
          ...List.generate(
              15,
              (index) => Positioned(
                    left: index * 40.0,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child:
                        Container(color: Colors.white.withValues(alpha: 0.03)),
                  )),
          Positioned(
            right: -20,
            bottom: 40,
            child: Transform.rotate(
              angle: -0.2,
              child: Opacity(
                opacity: 0.05,
                child: Text(
                  'PLATINUM\nPRESTIGE',
                  style: TextStyle(
                    color: const Color(0xFF102A43),
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    height: 0.8,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.wifi_rounded,
                            color: Color(0xFF486581), size: 24),
                        Text(styles.tierName,
                            style: const TextStyle(
                                color: Color(0xFF486581),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.5)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFF102A43),
                          fontSize: 22,
                          letterSpacing: 4.5,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PLATINUM CARDHOLDER',
                                style: TextStyle(
                                    color: Color(0xFF486581),
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFF102A43),
                                    fontSize: 16,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('BALANCE DISPONIBLE',
                            style: TextStyle(
                                color: Color(0xFF486581),
                                fontSize: 7,
                                fontWeight: FontWeight.w900)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OdometerWidget(
                                value: balance,
                                color: const Color(0xFF102A43),
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF102A43))),
                            const SizedBox(width: 8),
                            _buildCardNetworkLogo(isVisa: true),
                          ],
                        ),
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

  Widget _buildBlackCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black,
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 5)
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CarbonFiberPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 32),
                    Text(styles.tierName,
                        style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4)),
                  ],
                ),
                const Spacer(),
                _buildEmvChipDesign(isBlack: true),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 20,
                          letterSpacing: 5,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OdometerWidget(
                            value: balance,
                            color: const Color(0xFFD4AF37),
                            style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFD4AF37))),
                        const SizedBox(width: 8),
                        _buildCardNetworkLogo(isVisa: false),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_getRandomQuote(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                        fontSize: 9,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmvChipDesign({bool isBlack = false}) {
    return Container(
      width: 45,
      height: 35,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: isBlack
                ? [Colors.grey.shade800, Colors.grey.shade600]
                : [Colors.amber.shade200, Colors.amber.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isBlack ? Colors.white24 : Colors.amber.shade700, width: 1),
      ),
      child: Stack(
        children: [
          Center(child: Container(width: 45, height: 1, color: Colors.black12)),
          Center(child: Container(width: 1, height: 35, color: Colors.black12)),
        ],
      ),
    );
  }

  Widget _buildCardNetworkLogo({required bool isVisa}) {
    if (isVisa) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('VISA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              )),
          Container(width: 30, height: 2, color: Colors.amber),
        ],
      );
    } else {
      return SizedBox(
        width: 40,
        height: 25,
        child: Stack(
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  shape: BoxShape.circle),
            ),
            Positioned(
              left: 12,
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.8),
                    shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildVipBlackCard({required double cardHeight}) {
    const goldDeep = Color(0xFFBF953F);
    const goldLight = Color(0xFFFCF6BA);
    const goldMid = Color(0xFFD4AF37);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: goldMid, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: goldMid.withValues(alpha: 0.4),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: goldDeep.withValues(alpha: 0.2),
              blurRadius: 48,
              spreadRadius: -4),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
              right: -60,
              top: -60,
              child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        goldMid.withValues(alpha: 0.15),
                        Colors.transparent
                      ])))),
          Positioned(
              left: -40,
              bottom: -40,
              child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        goldDeep.withValues(alpha: 0.2),
                        Colors.transparent
                      ])))),
          Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MONOPOLY BANK',
                              style: TextStyle(
                                  color: goldLight,
                                  fontSize: 9,
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w800)),
                          const Text('VIP BLACK EDITION',
                              style: TextStyle(
                                  color: goldMid,
                                  fontSize: 8,
                                  letterSpacing: 2.5,
                                  fontWeight: FontWeight.w700)),
                        ]),
                    Icon(Icons.diamond_rounded, color: goldLight, size: 30),
                  ],
                ),
                const Spacer(),
                _buildEmvChipDesign(),
                const SizedBox(height: 12),
                Text(_generateCardNumber(name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Courier',
                        fontSize: 18,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PLATINUM CARDHOLDER',
                                style: TextStyle(color: goldDeep, fontSize: 7)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OdometerWidget(
                            value: balance,
                            color: goldLight,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: goldLight)),
                        const SizedBox(width: 8),
                        _buildCardNetworkLogo(isVisa: true),
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

  _CardStyles _getStyles(CardTier tier, Color playerColor) {
    switch (tier) {
      case CardTier.standard:
        return _CardStyles(
          gradient: LinearGradient(
            colors: [
              playerColor,
              Color.lerp(playerColor, Colors.black, 0.4)!,
              Color.lerp(playerColor, Colors.black, 0.7)!
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'CLASSIC EDITION',
        );
      case CardTier.gold:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFBF953F),
              Color(0xFFFCF6BA),
              Color(0xFFB38728),
              Color(0xFFFBF5B7),
              Color(0xFFFBF5B7)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: const Color(0xFF2D2410),
          tierName: 'GOLD MEMBERSHIP',
        );
      case CardTier.platinum:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD), Color(0xFF757575)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'PLATINUM PRESTIGE',
        );
      case CardTier.black:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.blueAccent,
          tierName: 'ULTIMATE BLACK',
        );
    }
  }

  String _generateCardNumber(String source) {
    if (source.isEmpty) source = "JUGADOR";
    final seed = source
        .split('')
        .fold<int>(0, (prev, char) => prev + char.codeUnitAt(0));
    final rand = Random(seed);

    String part() => (rand.nextInt(9000) + 1000).toString().padLeft(4, '0');
    return "${part()} ${part()} ${part()} ${part()}";
  }

  String _getRandomQuote() {
    final quotes = [
      "Tu sueldo es mi propina.",
      "Demasiado rico para tener gusto.",
      "Mi única Bill es Gates.",
      "Compré el banco para no esperar.",
      "No hablo idioma 'descuento'.",
      "Más burbujas que tu cuenta.",
      "El caviar es mi snack.",
      "Oro para mis lentes.",
    ];
    return quotes[name.length % quotes.length];
  }
}
