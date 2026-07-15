part of '../bank_screen.dart';

mixin _BankConnection on State<BankScreen> {
  _BankScreenState get _self => this as _BankScreenState;

  void didChangeAppLifecycleState(AppLifecycleState state) {
    // no-op
  }

  Future<bool> _waitForPlayerReady(
      _BankOperationDialogController dialog) async {
    final transport = P2PService().wsTransport;
    final notifier = transport.connectedPlayersNotifier;

    bool hasReadyPlayer() => notifier.value.any(
          (player) =>
              player.connected &&
              player.name.trim().isNotEmpty &&
              player.deviceInstallationId.trim().isNotEmpty,
        );

    if (hasReadyPlayer()) return true;

    dialog.update(
      title: 'Preparando conexión',
      message: 'Esperando que el jugador se conecte...',
    );
    final completer = Completer<bool>();

    void finish(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    void playerListener() {
      if (hasReadyPlayer()) finish(true);
    }

    void cancelListener() {
      if (dialog.cancelled.value) finish(false);
    }

    notifier.addListener(playerListener);
    dialog.cancelled.addListener(cancelListener);
    final timeout = Timer(const Duration(seconds: 8), () => finish(false));
    playerListener();

    final result = await completer.future;
    timeout.cancel();
    notifier.removeListener(playerListener);
    dialog.cancelled.removeListener(cancelListener);
    return result;
  }

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
            p.playing &&
            p.name.isNotEmpty &&
            p.deviceInstallationId.isNotEmpty &&
            (excludePlayerId == null || p.name != excludePlayerId))
        .toList();

    if (players.isEmpty) {
      NotificationService().show(
        'No hay jugadores conectados disponibles',
        backgroundColor: kRed,
      );
      return null;
    }

    if (players.length == 1) {
      return players.first;
    }

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
            children: [
              for (final player in players) ...[
                GestureDetector(
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
                            color: _playerColor(player.colorId)
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
                                color: _playerColor(player.colorId),
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
                ),
              ],
            ],
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
    final players = P2PService()
        .wsTransport
        .connectedPlayersNotifier
        .value
        .where((p) =>
            p.connected &&
            p.playing &&
            p.name.isNotEmpty &&
            p.name != excludePlayerId)
        .toList();

    if (players.isEmpty) {
      players.addAll(P2PService()
          .wsTransport
          .connectedPlayersNotifier
          .value
          .where((p) => p.connected && p.name.isNotEmpty));
      players.removeWhere((p) => p.name == excludePlayerId);
    }

    if (players.isEmpty) return null;
    if (players.length == 1) return players.first;

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
