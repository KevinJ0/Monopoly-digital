part of '../bank_screen.dart';

mixin _BankBuilders on State<BankScreen> {
  _BankScreenState get _self => this as _BankScreenState;

  @override
  Widget build(BuildContext context) {
    final playerColor = context.watch<SessionProvider>().color;

    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        title: const Text(
          'Operaciones',
          style: TextStyle(
              color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: kTextSecondary),
            tooltip: 'Configuración',
            onPressed: _self._openSettings,
          ),
        ],
      ),
      body: MonopolyBackground(
        child: PlayerColorBackdrop(
        color: playerColor,
        child: SlideTransition(
          position: _self._slide,
          child: FadeTransition(
            opacity: _self._slideCtrl,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.viewPaddingOf(context).bottom + 128,
                  ),
                  child: Form(
                    key: _self._formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AnimatedEntry(
                          delay: Duration(milliseconds: 100),
                          child: _BankHeader(),
                        ),
                        const SizedBox(height: 24),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 180),
                          child: _buildConnectedPlayersList(),
                        ),
                        const SizedBox(height: 24),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 190),
                          child: _buildSpecialOperations(),
                        ),
                        const SizedBox(height: 24),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 200),
                          child: _buildOpSelector(),
                        ),
                        const SizedBox(height: 24),
                        if (_self._selectedOp != 'passGo')
                          AnimatedEntry(
                            delay: const Duration(milliseconds: 300),
                            child: _buildAmountField(),
                          ),
                        const SizedBox(height: 28),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 400),
                          child: _buildQuickAmounts(),
                        ),
                        const SizedBox(height: 32),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 500),
                          child: _buildSendButton(),
                        ),
                        const SizedBox(height: 40),
                        _buildTransactionHistory(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildOpSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPERACIÓN',
          style:
              TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        ...(_self._operations.map((op) => _buildOpTile(op))),
      ],
    );
  }

  Widget _buildOpTile(_OpOption op) {
    final selected = _self._selectedOp == op.id;
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        setState(() => _self._selectedOp = op.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? op.color.withValues(alpha: 0.12) : kBgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? op.color : kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(op.icon,
                color: selected ? op.color : kTextSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                op.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? op.color : kTextSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: op.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    final isFixedOp = _self._selectedOp == 'passGo' ||
        _self._selectedOp.startsWith('custom:');
    if (isFixedOp) {
      final fixedAmount = _self._fixedAmountForSelectedOp();
      return _buildFixedAmountDisplay(fixedAmount);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MONTO',
          style:
              TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _self._amountCtrl,
          onTap: () => SoundService.playClick(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
              color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: const TextStyle(
                color: kGreen, fontSize: 24, fontWeight: FontWeight.w700),
            hintText: '0',
            hintStyle: const TextStyle(color: kBorder, fontSize: 24),
            filled: true,
            fillColor: kBgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
              borderSide: const BorderSide(color: kGreen, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kRed),
            ),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Ingresa un monto';
            final n = double.tryParse(v.replaceAll(',', ''));
            if (n == null || n <= 0) return 'Monto inv\u00e1lido';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildFixedAmountDisplay(double amount) {
    final isGive = _self._isFixedOpGive();
    final color = isGive ? kGreen : kRed;
    final prefix = isGive ? '+' : '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MONTO FIJO',
          style:
              TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                isGive
                    ? Icons.add_circle_outline_rounded
                    : Icons.remove_circle_outline_rounded,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                '$prefix${formatMoney(amount)}',
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAmounts() {
    if (_self._selectedOp == 'passGo' ||
        _self._selectedOp.startsWith('custom:')) {
      return const SizedBox();
    }
    const presets = [50, 100, 200, 500, 1000, 2000];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((p) {
        return GestureDetector(
          onTap: () {
            SoundService.playClick();
            _self._amountCtrl.text = '$p';
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Text(
              formatMoney(p),
              style: const TextStyle(
                  color: kTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSendButton() {
    final op = _self._operations.firstWhere((o) => o.id == _self._selectedOp);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton.icon(
          onPressed: _self._sending ? null : _self._send,
          icon: _self._sending
              ? const AppSpinner(
                  size: 18,
                  color: Colors.black,
                )
              : Icon(op.icon),
          label: Text(
            _self._sending ? 'Enviando...' : op.label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: op.color,
            foregroundColor:
                op.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionHistory() {
    final ledger = BankLedgerService();
    final all = ledger.transactionHistory;
    final playerNames = all
        .map((tx) => tx['playerId'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final typeValues = all
        .map((tx) => tx['type'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    var filtered = all.where((tx) {
      if (_self._historyFilterPlayer != null &&
          tx['playerId'] != _self._historyFilterPlayer) {
        return false;
      }
      if (_self._historyFilterType != null &&
          tx['type'] != _self._historyFilterType) {
        return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) {
      int cmp;
      if (_self._historySortBy == 'amount') {
        cmp = ((a['amount'] as num?)?.toDouble() ?? 0)
            .compareTo((b['amount'] as num?)?.toDouble() ?? 0);
      } else {
        final ta = a['timestamp'] as String? ?? '';
        final tb = b['timestamp'] as String? ?? '';
        cmp = ta.compareTo(tb);
      }
      return _self._historySortAscending ? cmp : -cmp;
    });
    final displayed = filtered.take(50).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'HISTORIAL',
              style: TextStyle(
                  color: kTextSecondary, fontSize: 11, letterSpacing: 2),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: kBgCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${filtered.length}',
                style: const TextStyle(color: kTextSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: kBgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _self._historyFilterPlayer,
                    hint: const Text('Todos los jugadores',
                        style: TextStyle(color: kTextSecondary, fontSize: 12)),
                    dropdownColor: kBgCard,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Todos los jugadores',
                            style: TextStyle(color: kTextPrimary, fontSize: 12)),
                      ),
                      ...playerNames.map((name) => DropdownMenuItem(
                            value: name,
                            child: Text(name,
                                style: const TextStyle(
                                    color: kTextPrimary, fontSize: 12)),
                          )),
                    ],
                    onChanged: (v) =>
                        setState(() => _self._historyFilterPlayer = v),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: kBgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _self._historyFilterType,
                    hint: const Text('Todos los tipos',
                        style: TextStyle(color: kTextSecondary, fontSize: 12)),
                    dropdownColor: kBgCard,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Todos los tipos',
                            style: TextStyle(color: kTextPrimary, fontSize: 12)),
                      ),
                      ...typeValues.map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(_txLabel(t),
                                style: const TextStyle(
                                    color: kTextPrimary, fontSize: 12)),
                          )),
                    ],
                    onChanged: (v) =>
                        setState(() => _self._historyFilterType = v),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: kBgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _self._historySortBy,
                    dropdownColor: kBgCard,
                    items: const [
                      DropdownMenuItem(
                        value: 'date',
                        child: Text('Ordenar por fecha',
                            style: TextStyle(
                                color: kTextPrimary, fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'amount',
                        child: Text('Ordenar por monto',
                            style: TextStyle(
                                color: kTextPrimary, fontSize: 12)),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _self._historySortBy = v!),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(
                  () => _self._historySortAscending = !_self._historySortAscending),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kBgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: Icon(
                  _self._historySortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: kTextSecondary,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (displayed.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kBgCard.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Sin transacciones',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          )
        else
          ...displayed.map((tx) => _buildHistoryTile(tx)),
      ],
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final playerId = tx['playerId'] as String? ?? '';
    final timestamp = tx['timestamp'] as String? ?? '';
    final dt = DateTime.tryParse(timestamp);
    final time = dt != null ? _format12h(dt) : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kBgCard.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(_txIcon(type), size: 16, color: _txColor(type)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _txLabel(type),
                  style: const TextStyle(
                      color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  playerId,
                  style: const TextStyle(color: kTextSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(0)}',
            style: TextStyle(
              color: _txColor(type),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            time,
            style: const TextStyle(color: kTextSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedPlayersList() {
    final transport = P2PService().wsTransport;
    return ValueListenableBuilder<List<WsPlayer>>(
      valueListenable: transport.connectedPlayersNotifier,
      builder: (context, players, _) {
        if (players.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kBgCard.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups_rounded,
                        color: kGreen, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Jugadores conectados',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${players.length}',
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...players.map((player) => _buildPlayerTile(player)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerTile(WsPlayer player) {
    final ledger = BankLedgerService();
    final account = ledger.accountFor(player.displayName);
    final playerColor = _playerColor(player.colorId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _self._showPlayerDetailDialog(player, account),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: playerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text(
                  player.avatarId.isNotEmpty ? player.avatarId : '\u{1F464}',
                  style: TextStyle(fontSize: 16, color: playerColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'WiFi Direct',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (account != null)
              Text(
                formatMoney(account.balance),
                style: TextStyle(
                  color: account.bankrupt ? kRed : kGreen,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: kGreen,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInfoTab({
    required WsPlayer player,
    required double balance,
    required double volume,
    required int passGoCount,
    required int txCount,
    required String tier,
    required String tierLabel,
    required Color tierColor,
    BankPlayerAccount? account,
    List<Map<String, dynamic>> transactions = const [],
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Tarjeta del Jugador'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColor.withValues(alpha: 0.18),
                  tierColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: tierColor.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _playerColor(player.colorId)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _playerColor(player.colorId)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      player.avatarId.isNotEmpty
                          ? player.avatarId
                          : '\u{1F464}',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tierLabel,
                        style: TextStyle(
                          color: tierColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Nivel ${_tierLevel(tier)}',
                        style: TextStyle(
                          color: tierColor.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildSectionHeader('Resumen'),
          _detailRow('Nombre', player.displayName),
          _detailRow('Dirección IP', player.address.isNotEmpty ? player.address : '-'),
          _detailRow('Conexi\u00f3n', 'WiFi'),
          const SizedBox(height: 12),
          _buildSectionHeader('Finanzas'),
          _detailRow('Saldo', formatMoney(balance)),
          _detailRow('Volumen total',
              formatMoney(volume)),
          _detailRow(
              'Pases por GO', '$passGoCount'),
          _detailRow('Transacciones',
              '$txCount realizadas'),
          if (account != null && account.investedAmount > 0) ...[
            const SizedBox(height: 12),
            _buildSectionHeader('Inversi\u00f3n Activa'),
            _detailRow('Invertido',
                formatMoney(account.investedAmount)),
            _detailRow('Generado',
                formatMoney(account.generatedAmount)),
            _detailRow('Progreso',
                '${account.currentPasses} / ${account.targetPasses} pases'),
          ],
          if (account != null && account.bankrupt) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: kRed.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gavel_rounded, color: kRed, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Jugador en Bancarrota',
                      style: TextStyle(
                        color: kRed,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (transactions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionHeader(
                '\u00daltimas Transacciones (${transactions.length})'),
            ...transactions.take(5).map((tx) {
              final type = tx['type'] as String? ?? '';
              final amount =
                  (tx['amount'] as num?)?.toDouble() ?? 0;
              final timestamp = tx['timestamp'] as String? ?? '';
              final dt = DateTime.tryParse(timestamp);
              final time = dt != null ? _format12h(dt) : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_txIcon(type), size: 14,
                        color: _txColor(type)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _txLabel(type),
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Text(
                      '\$${amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: _txColor(type),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      time,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectionInfoTab(WsPlayer player) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Dispositivo'),
          _detailRow('Nombre',
              player.name.isNotEmpty ? player.name : '-'),
          _detailRow(
              'Conexi\u00f3n', 'WiFi Direct'),
          _detailRow('ID', player.id),
          _detailRow(
              'ID Instalaci\u00f3n',
              player.deviceInstallationId.isNotEmpty
                  ? player.deviceInstallationId
                  : '-'),
          const SizedBox(height: 12),
          _buildSectionHeader('Estado'),
          _detailRow('Handshake',
              player.playing ? 'Completado' : 'Pendiente'),
          _detailRow('Conectado',
              player.connected ? 'S\u00ed' : 'No'),
          const SizedBox(height: 12),
          _detailRow(
              '\u00daltima actividad',
              _format12h(player.lastSeen)),
        ],
      ),
    );
  }

  String _playerTier(double balance) {
    if (balance >= 15000) return 'black';
    if (balance >= 8000) return 'platinum';
    if (balance >= 4000) return 'gold';
    return 'standard';
  }

  String _tierLabel(String tier) {
    return switch (tier) {
      'black' => 'ULTIMATE BLACK',
      'platinum' => 'PLATINUM PRESTIGE',
      'gold' => 'GOLD MEMBERSHIP',
      _ => 'CLASSIC EDITION',
    };
  }

  int _tierLevel(String tier) {
    return switch (tier) {
      'standard' => 1,
      'gold' => 2,
      'platinum' => 3,
      'black' => 4,
      _ => 1,
    };
  }

  Color _tierColor(String tier) {
    return switch (tier) {
      'standard' => const Color(0xFF90A4AE),
      'gold' => const Color(0xFFFFD700),
      'platinum' => const Color(0xFF1E88E5),
      'black' => const Color(0xFF424242),
      _ => const Color(0xFF90A4AE),
    };
  }

  Color _playerColor(String colorId) {
    const colors = [
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
    final index = int.tryParse(colorId) ?? 0;
    if (index >= 0 && index < colors.length) return colors[index];
    return colors[0];
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: kGold,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _txLabel(String type) {
    if (type.startsWith('custom_')) {
      final customId = type.substring('custom_'.length);
      final match = BankSettingsService()
          .customOps
          .where((c) => c.id == customId)
          .firstOrNull;
      return match?.name ?? type;
    }
    return switch (type) {
      'payment' => 'Pago del banco',
      'charge' => 'Cobro del banco',
      'passGo' => 'Pas\u00f3 por GO',
      'handshake_initial' => 'Handshake inicial',
      'handshake_reconnect' => 'Reconexi\u00f3n',
      'bankruptcy' => 'Bancarrota',
      'investment_opened' => 'Inversi\u00f3n abierta',
      'investment_completed' => 'Inversi\u00f3n completada',
      'investment_early_withdrawal' => 'Retiro anticipado',
      'transfer_held' => 'Retenci\u00f3n de transferencia',
      'transfer_received' => 'Transferencia recibida',
      'transfer_cancelled' => 'Transferencia devuelta',
      _ => type,
    };
  }

  IconData _txIcon(String type) {
    if (type.startsWith('custom_')) {
      final customId = type.substring('custom_'.length);
      final match = BankSettingsService()
          .customOps
          .where((c) => c.id == customId)
          .firstOrNull;
      if (match != null) {
        return BankSettingsService.availableIcons[match.iconKey] ??
            Icons.payments_rounded;
      }
    }
    return switch (type) {
      'payment' => Icons.arrow_downward_rounded,
      'charge' => Icons.arrow_upward_rounded,
      'passGo' => Icons.flag_rounded,
      'handshake_initial' => Icons.handshake_rounded,
      'handshake_reconnect' => Icons.handshake_rounded,
      'bankruptcy' => Icons.gavel_rounded,
      'investment_opened' => Icons.trending_up_rounded,
      'investment_completed' => Icons.trending_up_rounded,
      'investment_early_withdrawal' => Icons.trending_up_rounded,
      'transfer_held' => Icons.lock_outline_rounded,
      'transfer_received' => Icons.arrow_downward_rounded,
      'transfer_cancelled' => Icons.replay_rounded,
      _ => Icons.swap_horiz_rounded,
    };
  }

  Color _txColor(String type) {
    if (type.startsWith('custom_')) {
      final customId = type.substring('custom_'.length);
      final match = BankSettingsService()
          .customOps
          .where((c) => c.id == customId)
          .firstOrNull;
      return match?.isGive == true ? kGreen : kRed;
    }
    return switch (type) {
      'payment' || 'passGo' || 'transfer_received' => kGreen,
      'charge' || 'bankruptcy' => kRed,
      'transfer_held' => kGold,
      'transfer_cancelled' || 'transfer_delivered' => Colors.orange,
      _ => kGold,
    };
  }

  Widget _buildSpecialOperations() {
    return ValueListenableBuilder<int>(
      valueListenable: BankLedgerService().heldTransfersCount,
      builder: (context, count, _) {
        if (count == 0 && !kDebugMode) return const SizedBox.shrink();
        final held = BankLedgerService().heldTransfers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'OPERACIONES ESPECIALES',
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Transacciones Incompletas',
              style: TextStyle(
                color: kGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...held.map((ht) => _buildHeldTransferTile(ht)),
            if (held.isEmpty && kDebugMode) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBgCard.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: const Text(
                  'No hay transacciones retenidas.',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ),
            ],

          ],
        );
      },
    );
  }

  Widget _buildHeldTransferTile(HeldTransfer ht) {
    final timeAgo = _formatTimeAgo(ht.heldAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_top_rounded,
                  color: Colors.orange.withValues(alpha: 0.8), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'De: ${ht.fromPlayerId}',
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                formatMoney(ht.amount),
                style: const TextStyle(
                  color: kGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Retenido hace $timeAgo',
            style: const TextStyle(
              color: kTextSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _resolveHeldTransfer(ht, returnToSender: true),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Devolver'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _resolveHeldTransfer(ht, returnToSender: false),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Entregar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kGreen,
                    side: const BorderSide(color: kGreen),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  String _format12h(DateTime dt) {
    final h = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  Future<void> _resolveHeldTransfer(
    HeldTransfer ht, {
    required bool returnToSender,
  }) async {
    if (returnToSender) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Devolver dinero',
              style: TextStyle(color: kTextPrimary)),
          content: Text(
            'Se devolverán ${formatMoney(ht.amount)} a ${ht.fromPlayerId}.',
            style: const TextStyle(color: kTextSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Devolver'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final credited = await BankLedgerService().credit(
          ht.fromPlayerId,
          ht.amount,
          type: 'transfer_cancelled',
          counterpartyId: 'Banco',
        );
        await BankLedgerService().removeHeldTransfer(ht.id);
        if (mounted) {
          NotificationService().show(
            'Dinero devuelto a ${ht.fromPlayerId}',
            backgroundColor: Colors.orange,
          );
        }
        try {
          await _self._sendToConnectedPlayer(credited.toClientPayload());
        } on TransportUnavailableException catch (e) {
          if (mounted) {
            NotificationService().show(
              'Dinero devuelto a ${ht.fromPlayerId}, sin confirmación: ${e.transportName}. Se sincronizará al reconectar.',
              backgroundColor: Colors.orange,
            );
          }
        }
      } catch (e, s) {
        if (mounted) context.showFriendlyError(e, s);
      }
    } else {
      final receiver = await _self._selectTransferReceiver(
        excludePlayerId: ht.fromPlayerId,
      );
      if (receiver == null) {
        if (mounted) {
          NotificationService().show(
            'No hay un jugador receptor disponible.',
            backgroundColor: Colors.orange,
          );
        }
        return;
      }
      final receiverName = receiver.displayName;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Entregar dinero',
              style: TextStyle(color: kTextPrimary)),
          content: Text(
            'Se entregarán ${formatMoney(ht.amount)} a $receiverName.',
            style: const TextStyle(color: kTextSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Entregar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final dialog = _BankOperationDialogController(
        transportType: TransportType.ws,
      );
      var dialogOpen = true;
      _self._showOperationDialog(dialog).whenComplete(() {
        dialogOpen = false;
      });
      await Future<void>.delayed(Duration.zero);

      try {
        dialog.update(
          title: 'Entregando dinero',
          message: 'Enviando ${formatMoney(ht.amount)} a $receiverName...',
        );

        final delivered = await BankLedgerService().credit(
          receiverName,
          ht.amount,
          type: 'transfer_received',
          counterpartyId: ht.fromPlayerId,
        );
        try {
          await _self._sendToConnectedPlayer(delivered.toClientPayload());
        } on TransportUnavailableException catch (e) {
          await _self._failOperationDialog(
            dialog,
            'Entrega sin confirmación',
            'Dinero acreditado a $receiverName, pero el dispositivo no confirmó: ${e.transportName}. Se sincronizará al reconectar.',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
          );
          await BankLedgerService().removeHeldTransfer(ht.id);
          return;
        }
        try {
          final senderNote = await BankLedgerService().credit(
            ht.fromPlayerId,
            0,
            type: 'transfer_delivered',
            counterpartyId: receiverName,
          );
          final senderPlayer = P2PService()
              .wsTransport
              .connectedPlayersNotifier
              .value
              .where((p) => p.connected && p.name == ht.fromPlayerId)
              .firstOrNull;
          if (senderPlayer != null) {
            await _self._sendToConnectedPlayer(senderNote.toClientPayload());
          }
        } catch (_) {}
        await BankLedgerService().removeHeldTransfer(ht.id);
        SoundService.playSuccess();
        HapticFeedback.mediumImpact();
        dialog.complete(
          'Dinero entregado a $receiverName.',
        );
        NotificationService().show(
          'Dinero entregado a $receiverName',
          backgroundColor: kGreen,
        );
      } catch (e, s) {
        if (dialogOpen && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        if (mounted) context.showFriendlyError(e, s);
      }
    }
  }

}
