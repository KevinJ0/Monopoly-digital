part of '../wallet_screen.dart';

mixin _WalletIncoming on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;

  final Set<String> _seenBankTxIds = {};

  void _listenForIncoming() {
    final wallet = context.read<WalletController>();
    final session = context.read<SessionProvider>();

    _self._payloadSub ??= P2PService().payloadStream.listen((payload) async {
      if (!mounted) return;
      final txId = payload['txId'] as String?;
      if (txId != null) {
        if (_seenBankTxIds.contains(txId)) return;
        _seenBankTxIds.add(txId);
        if (_seenBankTxIds.length > 80) {
          _seenBankTxIds.remove(_seenBankTxIds.first);
        }
      }
      final type = payload['type'] as String?;

      if (type == 'bank_state_ack') {
        final bankTxId = payload['bankTxId'] as String?;
        debugPrint('[BANK] bank_state_ack received bankTxId=$bankTxId hasCompleter=${_self._bankDeliveryAcks.containsKey(bankTxId)}');
        if (bankTxId != null) {
          final completer = _self._bankDeliveryAcks[bankTxId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload);
            debugPrint('[BANK] bank_state_ack completed for bankTxId=$bankTxId');
          }
        }
        return;
      }

      final deviceInstallationId =
          (payload['deviceInstallationId'] as String?)?.trim();
      if (deviceInstallationId != null &&
          deviceInstallationId.isNotEmpty &&
          BankLedgerService().isDeviceBanned(deviceInstallationId)) {
        final playerId = ((payload['playerId'] as String?) ??
                (payload['name'] as String?) ??
                'Jugador')
            .trim();
        await _sendBlockedDeviceState(
          playerId,
          transportType: TransportType.ws,
          targetInstallationId: deviceInstallationId,
        );
        return;
      }

      if (type == 'ws_identity') {
        debugPrint('[BANK_WS] ws_identity received deviceId=$deviceInstallationId name=${payload['name']}');
      }
      if (type == 'ws_identity' &&
          deviceInstallationId != null &&
          deviceInstallationId.isNotEmpty) {
        debugPrint('[BANK_WS] Processing ws_identity');
        final playerId = ((payload['playerId'] as String?) ??
                (payload['name'] as String?) ??
                '')
            .trim();

        if (playerId.isEmpty) {
          final deviceAccount =
              BankLedgerService().accountForDeviceId(deviceInstallationId);
          if (deviceAccount != null && !deviceAccount.bankrupt) {
            debugPrint('[BANK_WS] Returning device with cleared local data: ${deviceAccount.playerId}');
            final storedName = deviceAccount.playerId;
            if (storedName.isNotEmpty) {
              P2PService().wsTransport.updatePlayerIdentity(
                deviceInstallationId: deviceInstallationId,
                name: storedName,
                avatarId: deviceAccount.avatarId.isNotEmpty
                    ? deviceAccount.avatarId
                    : (payload['avatarId'] ?? '👤'),
                colorId: deviceAccount.colorId.isNotEmpty
                    ? deviceAccount.colorId
                    : (payload['colorId'] ?? '0'),
              );
            }
            final restorePayload = <String, dynamic>{
              'type': 'handshake',
              'targetPlayerId': deviceAccount.playerId,
              'targetInstallationId': deviceInstallationId,
              'avatarId': deviceAccount.avatarId.isNotEmpty
                  ? deviceAccount.avatarId
                  : (payload['avatarId'] ?? '👤'),
              'colorId': deviceAccount.colorId.isNotEmpty
                  ? deviceAccount.colorId
                  : (payload['colorId'] ?? '0'),
              'gameId': 'monopoly',
              'name': deviceAccount.playerId,
              'eventType': 'handshake_restore',
              'amount': 0,
              'bankSessionId': BankLedgerService().currentBankSessionId,
              'bankDeviceId': DeviceIdentityService.installationId,
              ...deviceAccount.toClientState(),
            };
            P2PService().setTransport(TransportType.ws);
            try {
              await P2PService().sendPayload(restorePayload);
            } on TransportUnavailableException {
              // se reintenta en la próxima identidad
            }
          } else {
            debugPrint('[BANK_WS] New device, sending new_player');
            P2PService().setTransport(TransportType.ws);
            await P2PService().sendPayload({
              'type': 'new_player',
              'targetInstallationId': deviceInstallationId,
              'deviceInstallationId': deviceInstallationId,
            });
          }
          return;
        }

        final existingAccount = BankLedgerService().accountFor(playerId);
        final nameBelongsToAnotherDevice = playerId.isNotEmpty &&
            existingAccount != null &&
            existingAccount.deviceInstallationId.isNotEmpty &&
            existingAccount.deviceInstallationId != deviceInstallationId;
        if (nameBelongsToAnotherDevice) {
          await _sendBankError(
            playerId,
            'El nombre "$playerId" ya pertenece a otro jugador de esta partida. Elige un nombre diferente.',
            transportType: TransportType.ws,
          );
          return;
        }
        final isReturningPlayer = existingAccount != null &&
            !existingAccount.bankrupt &&
            existingAccount.deviceInstallationId == deviceInstallationId;
        final playerNeedsHandshake =
            (payload['isHandshakeDone'] as bool?) != true;
        if (isReturningPlayer && playerNeedsHandshake) {
          final restorePayload = <String, dynamic>{
            'type': 'handshake',
            'targetPlayerId': playerId,
            'targetInstallationId': existingAccount.deviceInstallationId,
            'avatarId': payload['avatarId'] ?? session.avatarId,
            'colorId': payload['colorId'] ?? session.colorId,
            'gameId': 'monopoly',
            'name': payload['name'] ?? session.name,
            'eventType': 'handshake_restore',
            'amount': 0,
            'bankSessionId': BankLedgerService().currentBankSessionId,
            'bankDeviceId': DeviceIdentityService.installationId,
            ...existingAccount.toClientState(),
          };
          P2PService().setTransport(TransportType.ws);
          try {
            await P2PService().sendPayload(restorePayload);
          } on TransportUnavailableException {
            // se reintenta en la próxima identidad
          }
        } else if (isReturningPlayer) {
          final syncResult = BankLedgerResult(
            account: existingAccount,
            transactionId: 'sync-${DateTime.now().microsecondsSinceEpoch}',
            eventType: 'bank_sync',
            amount: 0,
            bankSessionId: BankLedgerService().currentBankSessionId,
          );
          await _sendBankResult(
            syncResult,
            transportType: TransportType.ws,
          );
        } else {
          final result = await BankLedgerService().ensurePlayer(
            playerId,
            BankSettingsService().initialBalance,
            deviceInstallationId: deviceInstallationId,
          );
          final handshake = <String, dynamic>{
            'type': 'handshake',
            'targetPlayerId': playerId,
            'targetInstallationId': deviceInstallationId,
            'avatarId': payload['avatarId'] ?? session.avatarId,
            'colorId': payload['colorId'] ?? session.colorId,
            'gameId': 'monopoly',
            'name': payload['name'] ?? session.name,
            'bankTxId': result.transactionId,
            'eventType': result.eventType,
            'amount': result.amount,
            'bankSessionId': BankLedgerService().currentBankSessionId,
            'bankDeviceId': DeviceIdentityService.installationId,
            ...result.account.toClientState(),
          };
          P2PService().setTransport(TransportType.ws);
          debugPrint('[BANK_WS] Sending handshake to $playerId balance=${handshake['balance']}');
          try {
            await P2PService().sendPayload(handshake);
            debugPrint('[BANK_WS] Handshake sent successfully');
          } on TransportUnavailableException {
            debugPrint('[BANK_WS] TransportUnavailableException sending handshake');
          }
        }
        return;
      }

      if (type == 'player_profile') {
        final name = payload['name'] as String?;
        final avatarId = payload['avatarId'] as String? ?? '';
        final colorId = payload['colorId'] as String? ?? '0';
        final deviceId = payload['deviceInstallationId'] as String? ?? '';
        if (name != null && name.isNotEmpty) {
          debugPrint('[BANK_WS] player_profile name=$name avatarId=$avatarId colorId=$colorId');
          P2PService().wsTransport.updatePlayerIdentity(
            deviceInstallationId: deviceId,
            name: name,
            avatarId: avatarId,
            colorId: colorId,
          );
          final result = await BankLedgerService().ensurePlayer(
            name,
            BankSettingsService().initialBalance,
            deviceInstallationId: deviceId,
            avatarId: avatarId,
            colorId: colorId,
          );
          final handshake = <String, dynamic>{
            'type': 'handshake',
            'targetPlayerId': name,
            'targetInstallationId': deviceId,
            'avatarId': avatarId,
            'colorId': colorId,
            'gameId': 'monopoly',
            'name': name,
            'bankTxId': result.transactionId,
            'eventType': result.eventType,
            'amount': result.amount,
            'bankSessionId': BankLedgerService().currentBankSessionId,
            'bankDeviceId': DeviceIdentityService.installationId,
            ...result.account.toClientState(),
          };
          P2PService().setTransport(TransportType.ws);
          debugPrint('[BANK_WS] player_profile handshake to $name balance=${handshake['balance']}');
          try {
            await P2PService().sendPayload(handshake);
            debugPrint('[BANK_WS] player_profile handshake sent to $name');
          } on TransportUnavailableException {
            debugPrint('[BANK_WS] TransportUnavailableException sending player_profile handshake');
          }
        }
        return;
      }

      if (type == 'bank_operation_request') {
        await _handleBankOperationRequest(payload);
        wallet.refreshHistory();
        return;
      }

      if (type == 'transfer_hold_request') {
        await _handleBankTransferHoldRequest(payload);
        wallet.refreshHistory();
        return;
      }
    }, onError: (e, s) {
      if (mounted) _self._safeShowFriendlyError(e, s);
    });
  }

  String? _connectedPlayerIdForPayload(Map<String, dynamic> payload) {
    final claimed = payload['playerId'] as String?;
    if (claimed?.trim().isNotEmpty == true) return claimed!.trim();
    final fromPlayer = payload['fromPlayerId'] as String?;
    if (fromPlayer?.trim().isNotEmpty == true) return fromPlayer!.trim();
    return null;
  }

  Future<void> _handleBankOperationRequest(Map<String, dynamic> payload) async {
    final playerId = _connectedPlayerIdForPayload(payload);
    if (playerId == null) return;
    final requestId = payload['requestId'] as String?;

    try {
      final ledger = BankLedgerService();
      final operation = payload['operation'] as String?;
      final BankLedgerResult result;
      if (operation == 'invest') {
        final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
        final passes = (payload['passes'] as num?)?.toInt() ?? 0;
        result = await ledger.invest(playerId, amount, passes);
        NotificationService().show(
          '$playerId invirti\u00f3 ${formatMoney(amount)} a $passes pases por GO',
          backgroundColor: kGold,
          duration: const Duration(seconds: 4),
          dedupeKey: 'invest-$playerId',
        );
      } else if (operation == 'withdraw_investment') {
        result = await ledger.withdrawInvestment(playerId);
        NotificationService().show(
          '$playerId retir\u00f3 su inversi\u00f3n',
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          dedupeKey: 'withdraw-$playerId',
        );
      } else {
        throw const BankLedgerException('Operaci\u00f3n bancaria desconocida.');
      }
      await _sendBankResult(
        result,
        transportType: TransportType.ws,
        requestId: requestId,
      );
    } on BankLedgerException catch (error) {
      await _sendBankError(
        playerId,
        error.message,
        transportType: TransportType.ws,
        requestId: requestId,
      );
    }
  }

  Future<void> _sendBankResult(
    BankLedgerResult result, {
    TransportType transportType = TransportType.ws,
    String? requestId,
  }) async {
    final payload = result.toClientPayload();
    if (requestId != null) payload['requestId'] = requestId;
    debugPrint('[BANK] _sendBankResult targetPlayerId=${payload['targetPlayerId']} bankTxId=${result.transactionId} balance=${payload['balance']} type=${payload['type']}');
    final completer = Completer<Map<String, dynamic>>();
    _self._bankDeliveryAcks[result.transactionId] = completer;
    try {
      P2PService().setTransport(transportType);
      await P2PService().sendPayload(payload);

      debugPrint('[BANK] _sendBankResult waiting for ack...');
      final confirmation =
          await completer.future.timeout(const Duration(seconds: 12));
      debugPrint('[BANK] _sendBankResult ack received confirmedPlayer=${confirmation['playerId']} confirmedBalance=${confirmation['appliedBalance']}');
      final confirmedPlayer = confirmation['playerId'] as String?;
      final confirmedBalance =
          (confirmation['appliedBalance'] as num?)?.toDouble();
      if (confirmedPlayer != result.account.playerId ||
          confirmedBalance == null ||
          (confirmedBalance - result.account.balance).abs() >= 0.001) {
        throw TransportUnavailableException(
          'El jugador respondi\u00f3, pero no confirm\u00f3 el saldo esperado.',
        );
      }
    } on TimeoutException {
      throw TransportUnavailableException(
        'El jugador no confirm\u00f3 que recibi\u00f3 y mostr\u00f3 la operaci\u00f3n.',
      );
    } finally {
      _self._bankDeliveryAcks.remove(result.transactionId);
    }
  }

  Future<void> _sendBankError(
    String playerId,
    String message, {
    TransportType transportType = TransportType.ws,
    String? requestId,
    String? targetInstallationId,
  }) async {
    final payload = {
      'type': 'bank_operation_error',
      'bankSessionId': BankLedgerService().currentBankSessionId,
      'targetPlayerId': playerId,
      if (targetInstallationId != null) 'targetInstallationId': targetInstallationId,
      'message': message,
      if (requestId != null) 'requestId': requestId,
    };
    P2PService().setTransport(transportType);
    await P2PService().sendPayload(payload);
  }

  Future<void> _sendBlockedDeviceState(
    String playerId, {
    required TransportType transportType,
    String? targetInstallationId,
  }) async {
    final payload = <String, dynamic>{
      'type': 'kick',
      'targetPlayerId': playerId,
      if (targetInstallationId != null) 'targetInstallationId': targetInstallationId,
      'playerId': playerId,
      'eventType': 'device_banned',
    };
    P2PService().setTransport(transportType);
    await P2PService().sendPayload(payload);
  }

  Future<void> _handleBankTransferHoldRequest(
      Map<String, dynamic> payload) async {
    final sourcePlayerId = _connectedPlayerIdForPayload(payload);
    if (sourcePlayerId == null || !mounted) return;
    final requestId = payload['requestId'] as String?;
    if (_self._bankTransferHoldDialogOpen) {
      await _sendBankError(
        sourcePlayerId,
        'El banco ya est\u00e1 procesando otra transferencia.',
        transportType: TransportType.ws,
        requestId: requestId,
      );
      return;
    }
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
    if (!amount.isFinite || amount <= 0) return;

    final fromName = sourcePlayerId;
    late final BankLedgerResult held;
    try {
      held = await BankLedgerService().debit(
        sourcePlayerId,
        amount,
        type: 'transfer_held',
        counterpartyId: 'Banco',
      );
      await _sendBankResult(held,
          transportType: TransportType.ws, requestId: requestId);
    } on BankLedgerException catch (error) {
      await _sendBankError(
        sourcePlayerId,
        error.message,
        transportType: TransportType.ws,
        requestId: requestId,
      );
      return;
    } on TransportUnavailableException catch (_) {
      if (!mounted) return;
      await BankLedgerService().registerHeldTransfer(
        id: held.transactionId,
        fromPlayerId: sourcePlayerId,
        amount: amount,
      );
      _self._bankTransferHoldDialogOpen = true;
      _self._dialogActive = true;
      await _showTransferDeliveryFailedDialog(sourcePlayerId, amount);
      return;
    }
    await BankLedgerService().registerHeldTransfer(
      id: held.transactionId,
      fromPlayerId: sourcePlayerId,
      amount: amount,
    );
    if (!mounted) return;
    _self._bankTransferHoldDialogOpen = true;
    _self._dialogActive = true;

    await showGameDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var sending = false;
        var completed = false;
        var settled = false;
        var message =
            'Selecciona el jugador receptor y pulsa entregar.';

        return StatefulBuilder(
          builder: (context, setDialogState) {
              Future<void> deliver() async {
                  if (sending || completed) return;
                  setDialogState(() {
                    sending = true;
                    message = 'Buscando jugador receptor...';
                  });

                  try {
                    final players = P2PService()
                        .wsTransport
                        .connectedPlayersNotifier
                        .value
                        .where((p) => p.connected && p.name != fromName)
                        .toList();
                final String? receiverName =
                    players.isNotEmpty ? players.first.displayName : null;
                if (receiverName == null) {
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    sending = false;
                    message =
                        'No hay jugadores disponibles. Conecta al receptor e intenta de nuevo.';
                  });
                  return;
                }

                if (!ctx.mounted) return;
                setDialogState(() {
                  message = 'Entregando dinero a $receiverName...';
                });
                final delivered = await BankLedgerService().credit(
                  receiverName,
                  amount,
                  type: 'transfer_received',
                  counterpartyId: fromName,
                );
                await _sendBankResult(
                  delivered,
                  transportType: TransportType.ws,
                );
                await BankLedgerService().removeHeldTransfer(held.transactionId);
                if (!ctx.mounted) return;
                setDialogState(() {
                  sending = false;
                  completed = true;
                  settled = true;
                  message = 'Proceso completado con el jugador $receiverName.';
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                });
              } catch (e, s) {
                if (!mounted || !ctx.mounted) return;
                _self._safeShowFriendlyError(e, s);
                setDialogState(() {
                  sending = false;
                  message = 'No se pudo entregar el dinero. Intenta de nuevo.';
                });
              }
            }

            return AlertDialog(
              backgroundColor: kBgCard,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: completed
                      ? kGreen.withValues(alpha: 0.45)
                      : kGold.withValues(alpha: 0.35),
                ),
              ),
              title: Text(
                completed ? 'Transferencia completada' : 'Dinero retenido',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 260,
                height: 226,
                child: Column(
                  children: [
                    Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.account_balance_wallet_rounded,
                      color: completed ? kGreen : kGold,
                      size: 72,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatMoney(amount),
                      style: const TextStyle(
                        color: kGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'De: ${fromName.isEmpty ? 'Jugador' : fromName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kTextSecondary,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!completed)
                  TextButton(
                    onPressed: sending
                        ? null
                        : () async {
                            SoundService.playClick();
                            if (!settled) {
                              setDialogState(() => sending = true);
                              try {
                                final refunded =
                                    await BankLedgerService().credit(
                                  sourcePlayerId,
                                  amount,
                                  type: 'transfer_cancelled',
                                  counterpartyId: 'Banco',
                                );
                                await _sendBankResult(
                                  refunded,
                                  transportType: TransportType.ws,
                                );
                              } catch (_) {
                                // El crédito al ledger ya se realizó.
                                // El jugador sincronizará al reconectarse.
                              }
                              await BankLedgerService()
                                  .removeHeldTransfer(held.transactionId);
                              settled = true;
                            }
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                          },
                    child: const Text('Cerrar'),
                  ),
                SizedBox(
                  width: completed ? double.infinity : 150,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: completed || sending ? null : deliver,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: completed ? kGreen : kGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: sending
                        ? const AppSpinner(
                            size: 18,
                            color: Colors.black,
                          )
                        : Icon(completed
                            ? Icons.check_rounded
                            : Icons.touch_app_rounded),
                    label: Text(
                      completed ? 'Completado' : 'Entregar',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      _self._dialogActive = false;
      _self._bankTransferHoldDialogOpen = false;
    });
  }

  Future<void> _showTransferDeliveryFailedDialog(
    String playerId,
    double amount,
  ) async {
    await showGameDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        title: const Text(
          'Transferencia pendiente de confirmaci\u00f3n',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty_rounded,
                  color: kGold, size: 64),
              const SizedBox(height: 12),
              Text(
                formatMoney(amount),
                style: const TextStyle(
                  color: kGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'De: $playerId',
                style: const TextStyle(color: kTextSecondary),
              ),
              const SizedBox(height: 16),
              const Text(
                'El jugador no confirm\u00f3 la recepci\u00f3n del d\u00e9bito. '
                'El dinero ya fue retenido en el banco. '
                'El estado se sincronizar\u00e1 en la pr\u00f3xima reconexi\u00f3n.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                SoundService.playClick();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      _self._dialogActive = false;
      _self._bankTransferHoldDialogOpen = false;
    });
  }
}
