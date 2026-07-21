part of '../bank_screen.dart';

mixin _BankConnection on State<BankScreen> {
  _BankScreenState get _self => this as _BankScreenState;

  Future<WsPlayer?> _selectTargetPlayer({
    required String title,
    String? excludePlayerId,
  }) async {
    final players = P2PService()
        .wsTransport
        .connectedPlayersNotifier
        .value
        .where((p) =>
            p.connected &&
            p.name.isNotEmpty &&
            (excludePlayerId == null || p.name != excludePlayerId))
        .toList();

    final result = await showDialog<WsPlayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: players.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(Icons.person_off_rounded,
                              color: kTextSecondary, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'No hay jugadores disponibles para entregar el dinero.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]
                : players.map((player) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, player),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kBgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _self._playerColor(player.colorId)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  player.avatarId.isNotEmpty
                                      ? player.avatarId
                                      : '\u{1F464}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: _self._playerColor(player.colorId),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                player.displayName,
                                style: const TextStyle(
                                  color: kTextPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: kTextSecondary, size: 20),
                          ],
                        ),
                      ),
                    )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _sendToConnectedPlayer(Map<String, dynamic> payload) async {
    final payloadType = payload['type'];
    final playerId = payload['targetPlayerId'];
    AppAuditLogger.instance.event('BANK_OP', 'send_to_player',
        data: {'type': payloadType, 'playerId': playerId});
    P2PService().setTransport(TransportType.ws);

    final bankTxId = payload['bankTxId'] as String?;
    final requiresConfirmation =
        (payload['type'] == 'bank_state' || payload['type'] == 'handshake') &&
            bankTxId != null;
    if (!requiresConfirmation) {
      await P2PService().sendPayload(payload);
      return;
    }

    final completer = Completer<Map<String, dynamic>>();
    _self._pendingDeliveryAcks[bankTxId] = completer;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        await P2PService().sendPayload(payload);
        try {
          final confirmation =
              await completer.future.timeout(const Duration(seconds: 6));
          final expectedPlayer = payload['targetPlayerId'] as String?;
          final confirmedPlayer = confirmation['playerId'] as String?;
          final expectedBalance = (payload['balance'] as num?)?.toDouble();
          final confirmedBalance =
              (confirmation['appliedBalance'] as num?)?.toDouble();
          final playerMatches = expectedPlayer == null ||
              (confirmedPlayer != null && confirmedPlayer == expectedPlayer);
          final balanceMatches = expectedBalance == null ||
              (confirmedBalance != null &&
                  (confirmedBalance - expectedBalance).abs() < 0.001);
          if (!playerMatches || !balanceMatches) {
            AppAuditLogger.instance.event('BANK_OP', 'confirmation_mismatch',
                data: {'expectedPlayer': expectedPlayer, 'confirmedPlayer': confirmedPlayer});
            throw TransportUnavailableException(
              'El jugador respondió, pero no confirmó el saldo esperado. La operación no se marcará como completada.',
            );
          }
          AppAuditLogger.instance.event('BANK_OP', 'send_confirmed',
              data: {'playerId': confirmedPlayer, 'balance': confirmedBalance});
          return;
        } on TimeoutException {
          if (attempt == 1) rethrow;
        }
      }
    } on TimeoutException {
      throw TransportUnavailableException(
        'El jugador no confirmó que recibió y mostró la operación. Verifica su pantalla y vuelve a intentarlo.',
      );
    } finally {
      _self._pendingDeliveryAcks.remove(bankTxId);
    }
  }

  Future<WsPlayer?> _selectTransferReceiver({
    required String excludePlayerId,
  }) async {
    return _selectTargetPlayer(
      title: 'Seleccionar receptor',
      excludePlayerId: excludePlayerId,
    );
  }

  String _playerNameLabel() {
    final knownName = _self._connectedPlayerName.trim();
    if (knownName.isNotEmpty && knownName != 'Jugador') return knownName;
    return 'Jugador';
  }

  String _operationWaitTitle() {
    return switch (_self._selectedOp) {
      'passGo' => 'Esperando Pass GO',
      'receive' => 'Esperando pago al jugador',
      'payment' => 'Esperando cobro al jugador',
      _ => 'Esperando operación',
    };
  }

  String _operationWaitMessage() {
    return switch (_self._selectedOp) {
      'passGo' => 'Enviando recompensa por pasar GO...',
      'receive' => 'Enviando dinero al jugador...',
      'payment' => 'Solicitando cobro al jugador...',
      _ => 'Procesando la operación...',
    };
  }}
