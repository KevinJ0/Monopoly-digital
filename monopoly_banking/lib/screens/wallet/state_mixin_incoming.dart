part of '../wallet_screen.dart';

mixin _WalletIncoming on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;
  void _listenForIncoming() {
    final wallet = context.read<WalletController>();
    final session = context.read<SessionProvider>();

    _self._payloadSub ??= P2PService().payloadStream.listen((payload) async {
      if (!mounted) return;
      final txId = payload['txId'] as String?;
      if (txId != null) {
        if (_self._seenTxIds.contains(txId)) return;
        _self._seenTxIds.add(txId);
        _self._seenTxIdOrder.add(txId);
        if (_self._seenTxIdOrder.length > 80) {
          final removed = _self._seenTxIdOrder.removeAt(0);
          _self._seenTxIds.remove(removed);
        }
      }
      final type = payload['type'] as String?;

      if (!session.isBank && type == 'bank_server_stopping') {
        _self._userRequestedBleDisconnect = true;
        _self._bleScanning = false;
        try {
          await P2PService().bleTransport.stopClientScan();
        } finally {
          _self._userRequestedBleDisconnect = false;
        }
        if (mounted) {
          _self._safeSetState(() {});
          NotificationService().show(
            'El banco apagó el servidor BLE. Has sido desconectado.',
            backgroundColor: kRed,
            duration: const Duration(seconds: 5),
            dedupeKey: 'ble-bank-disconnected',
          );
        }
        return;
      }

      if (session.isBank && type == 'bank_state_ack') {
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null) {
          final completer = _self._bankDeliveryAcks[bankTxId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload);
          }
        }
        return;
      }

      if (!session.isBank &&
          (type == 'bank_session_status' ||
              type == 'handshake' ||
              type == 'bank_state' ||
              type == 'bank_operation_error' ||
              type == 'bank_access_denied')) {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        final changed = await session.adoptBankSession(
          payload['bankSessionId'] as String?,
        );
        if (changed) {
          _self._setBleClientIdentity();
          NotificationService().show(
            'El banco terminó la partida anterior. Se inició una nueva partida.',
            backgroundColor: kGold,
            duration: const Duration(seconds: 5),
          );
          if (type != 'handshake') return;
        }
        if (type == 'bank_session_status') return;
      }

      if (session.isBank && type != 'ble_proximity') {
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
            transportType: _transportForIncomingPayload(payload),
          );
          final bleDeviceId = payload['_bleDeviceId'] as String?;
          if (bleDeviceId != null) {
            P2PService().bleTransport.markPlayerInactive(bleDeviceId);
            unawaited(_disconnectBannedBleClient(bleDeviceId));
          }
          return;
        }

        if (type == 'ble_identity' &&
            deviceInstallationId != null &&
            deviceInstallationId.isNotEmpty) {
          final playerId = ((payload['playerId'] as String?) ??
                  (payload['name'] as String?) ??
                  '')
              .trim();
          final existingAccount = BankLedgerService().accountFor(playerId);
          final nameBelongsToAnotherDevice = playerId.isNotEmpty &&
              existingAccount != null &&
              existingAccount.deviceInstallationId.isNotEmpty &&
              existingAccount.deviceInstallationId != deviceInstallationId;
          if (nameBelongsToAnotherDevice) {
            await _sendBankError(
              playerId,
              'El nombre "$playerId" ya pertenece a otro jugador de esta partida. Elige un nombre diferente.',
              transportType: _transportForIncomingPayload(payload),
            );
            final bleDeviceId = payload['_bleDeviceId'] as String?;
            if (bleDeviceId != null) {
              P2PService().bleTransport.markPlayerInactive(bleDeviceId);
            }
            return;
          }
          final isReturningPlayer = existingAccount != null &&
              !existingAccount.bankrupt &&
              existingAccount.deviceInstallationId == deviceInstallationId;
          final playerNeedsHandshake =
              (payload['isHandshakeDone'] as bool?) != true;
          final bleDeviceId = payload['_bleDeviceId'] as String?;
          if (isReturningPlayer && bleDeviceId != null) {
            P2PService().bleTransport.markPlayerActive(bleDeviceId);
          }
          if (isReturningPlayer && playerNeedsHandshake) {
            final restorePayload = <String, dynamic>{
              'type': 'handshake',
              'targetPlayerId': playerId,
              'avatarId': session.avatarId,
              'colorId': session.colorId,
              'gameId': 'monopoly',
              'name': session.name,
              'eventType': 'handshake_restore',
              'amount': 0,
              'bankSessionId': BankLedgerService().currentBankSessionId,
              ...existingAccount.toClientState(),
            };
            final sourceTransport = _transportForIncomingPayload(payload);
            P2PService().setTransport(sourceTransport);
            try {
              await P2PService().sendPayload(restorePayload);
            } on TransportUnavailableException {
              // La identidad se reenvía cuando el canal BLE termina de
              // suscribirse; ese segundo intento restaurará la sesión.
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
              transportType: _transportForIncomingPayload(payload),
            );
          } else {
            final sourceTransport = _transportForIncomingPayload(payload);
            final result = await BankLedgerService().ensurePlayer(
              playerId,
              kInitialBalance,
              deviceInstallationId: deviceInstallationId,
            );
            final handshake = <String, dynamic>{
              'type': 'handshake',
              'targetPlayerId': playerId,
              'avatarId': session.avatarId,
              'colorId': session.colorId,
              'gameId': 'monopoly',
              'name': session.name,
              'bankTxId': result.transactionId,
              'eventType': result.eventType,
              'amount': result.amount,
              'bankSessionId': BankLedgerService().currentBankSessionId,
              ...result.account.toClientState(),
            };
            P2PService().setTransport(sourceTransport);
            try {
              await P2PService().sendPayload(handshake);
            } on TransportUnavailableException {
              // La identidad BLE se repite al terminar la suscripción.
            }
          }
        }
      }

      if (session.isBank && type == 'bank_operation_request') {
        await _handleBankOperationRequest(payload);
        wallet.refreshHistory();
        return;
      }

      if (session.isBank && type == 'transfer_hold_request') {
        await _handleBankTransferHoldRequest(payload);
        wallet.refreshHistory();
        return;
      }

      if (type == 'handshake') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        if (!session.isHandshakeDone) {
          await session.applyHandshake(payload);
          _self._setBleClientIdentity();
          _self._triggerWelcomeAnimation(payload['name'] as String?);
        }
        await wallet.applyBankState(payload);
        try {
          await WidgetsBinding.instance.endOfFrame
              .timeout(const Duration(seconds: 1));
        } on TimeoutException {
          // El estado ya quedó persistido; la confirmación puede continuar.
        }
        try {
          await P2PService().sendPayload({
            'type': 'handshake_confirm',
            if (payload['bankTxId'] != null) 'bankTxId': payload['bankTxId'],
            'playerId': session.name,
            'name': session.name,
            'appliedBalance': wallet.balance,
            'deviceInstallationId': DeviceIdentityService.installationId,
          });
        } on TransportUnavailableException {
          // La confirmación no es crítica; el estado ya se aplicó.
        }
      } else if (type == 'handshake_confirm') {
        return;
      } else if (type == 'bank_state') {
        if (!session.isHandshakeDone) return;
        if (!_isPayloadForPlayer(payload, session.name)) return;
        await wallet.applyBankState(payload);
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null && bankTxId.isNotEmpty) {
          try {
            await WidgetsBinding.instance.endOfFrame
                .timeout(const Duration(seconds: 1));
          } on TimeoutException {
            // El estado ya fue persistido y notificado; confirmamos igualmente.
          }
          try {
            await P2PService().sendPayload({
              'type': 'bank_state_ack',
              'bankTxId': bankTxId,
              'playerId': session.name,
              'name': session.name,
              'appliedBalance': wallet.balance,
              'deviceInstallationId': DeviceIdentityService.installationId,
            });
          } on TransportUnavailableException {
            // El estado ya se aplicó; el ack es informativo.
          }
        }
        final requestId = payload['requestId'] as String?;
        if (requestId == _self._pendingBankOperationId) {
          final completer = _self._pendingBankOperationCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
        if (requestId != null &&
            requestId.startsWith('transfer-') &&
            _self._pendingTransferCompleter != null) {
          final completer = _self._pendingTransferCompleter;
          if (completer != null && !completer.isCompleted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!completer.isCompleted) completer.complete();
            });
          }
        }
      } else if (type == 'bank_operation_error') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        final message =
            (payload['message'] as String?) ?? 'El banco rechazó la operación.';
        final requestId = payload['requestId'] as String?;
        if (requestId == _self._pendingBankOperationId) {
          final completer = _self._pendingBankOperationCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.completeError(BankLedgerException(message));
          }
        } else if (requestId != null &&
            requestId.startsWith('transfer-') &&
            _self._pendingTransferCompleter != null) {
          final completer = _self._pendingTransferCompleter;
          if (completer != null && !completer.isCompleted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!completer.isCompleted) {
                completer.completeError(BankLedgerException(message));
              }
            });
          }
        } else {
          await _showBankOperationError(message);
        }
      } else if (type == 'bank_access_denied') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        _self._stopBleClient();
        await wallet.applyBankState(payload);
      }
    }, onError: (e, s) {
      if (mounted) _self._safeShowFriendlyError(e, s);
    });
  }

  bool _isPayloadForPlayer(Map<String, dynamic> payload, String playerId) {
    final target = payload['targetPlayerId'] as String?;
    return target == null || target == playerId;
  }

  String? _connectedPlayerIdForPayload(Map<String, dynamic> payload) {
    final deviceId = payload['_bleDeviceId'] as String?;
    if (deviceId != null) {
      for (final player
          in P2PService().bleTransport.connectedPlayersNotifier.value) {
        if (player.id == deviceId && player.displayName.trim().isNotEmpty) {
          return player.displayName;
        }
      }
    }
    final claimed = payload['playerId'] as String?;
    if (claimed?.trim().isNotEmpty == true) return claimed!.trim();
    final fromPlayer = payload['fromPlayerId'] as String?;
    if (fromPlayer?.trim().isNotEmpty == true) return fromPlayer!.trim();
    return null;
  }

  Future<void> _disconnectBannedBleClient(String bleDeviceId) async {
    try {
      await P2PService().bleTransport.disconnectClient(bleDeviceId);
    } catch (_) {}
  }

  TransportType _transportForIncomingPayload(Map<String, dynamic> payload) {
    if (payload['_bleDeviceId'] != null) return TransportType.ble;
    return P2PService().currentType;
  }

  Future<void> _handleBankOperationRequest(Map<String, dynamic> payload) async {
    final playerId = _connectedPlayerIdForPayload(payload);
    if (playerId == null) return;
    final sourceTransport = _transportForIncomingPayload(payload);
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
          '$playerId invirtió ${formatMoney(amount)} a $passes pases por GO',
          backgroundColor: kGold,
          duration: const Duration(seconds: 4),
          dedupeKey: 'invest-$playerId',
        );
      } else if (operation == 'withdraw_investment') {
        result = await ledger.withdrawInvestment(playerId);
        NotificationService().show(
          '$playerId retiró su inversión',
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          dedupeKey: 'withdraw-$playerId',
        );
      } else {
        throw const BankLedgerException('Operación bancaria desconocida.');
      }
      await _sendBankResult(
        result,
        transportType: sourceTransport,
        requestId: requestId,
      );
    } on BankLedgerException catch (error) {
      await _sendBankError(
        playerId,
        error.message,
        transportType: sourceTransport,
        requestId: requestId,
      );
    }
  }

  Future<void> _sendBankResult(
    BankLedgerResult result, {
    TransportType transportType = TransportType.ble,
    String? requestId,
  }) async {
    final payload = result.toClientPayload();
    if (requestId != null) payload['requestId'] = requestId;
    final completer = Completer<Map<String, dynamic>>();
    _self._bankDeliveryAcks[result.transactionId] = completer;
    try {
      P2PService().setTransport(transportType);
      await P2PService().sendPayload(payload);

      final confirmation =
          await completer.future.timeout(const Duration(seconds: 12));
      final confirmedPlayer = confirmation['playerId'] as String?;
      final confirmedBalance =
          (confirmation['appliedBalance'] as num?)?.toDouble();
      if (confirmedPlayer != result.account.playerId ||
          confirmedBalance == null ||
          (confirmedBalance - result.account.balance).abs() >= 0.001) {
        throw TransportUnavailableException(
          'El jugador respondió, pero no confirmó el saldo esperado.',
        );
      }
    } on TimeoutException {
      throw TransportUnavailableException(
        'El jugador no confirmó que recibió y mostró la operación.',
      );
    } finally {
      _self._bankDeliveryAcks.remove(result.transactionId);
    }
  }

  Future<void> _sendBankError(
    String playerId,
    String message, {
    TransportType transportType = TransportType.ble,
    String? requestId,
  }) async {
    final payload = {
      'type': 'bank_operation_error',
      'bankSessionId': BankLedgerService().currentBankSessionId,
      'targetPlayerId': playerId,
      'message': message,
      if (requestId != null) 'requestId': requestId,
    };
    P2PService().setTransport(transportType);
    await P2PService().sendPayload(payload);
  }

  Future<void> _sendBlockedDeviceState(
    String playerId, {
    required TransportType transportType,
  }) async {
    final payload = <String, dynamic>{
      'type': 'bank_access_denied',
      'bankSessionId': BankLedgerService().currentBankSessionId,
      'targetPlayerId': playerId,
      'balance': 0,
      'isBankrupt': true,
      'eventType': 'bankruptcy_blocked',
      'amount': 0,
      'vaultInvestedAmount': 0,
      'vaultGeneratedAmount': 0,
      'vaultTargetPasses': 0,
      'vaultCurrentPasses': 0,
    };
    P2PService().setTransport(transportType);
    await P2PService().sendPayload(payload);
  }

  Future<void> _showBankOperationError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Operación rechazada'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestBankOperation(Map<String, dynamic> request) async {
    final session = context.read<SessionProvider>();
    final transport = P2PService().bleTransport;
    if (!session.isHandshakeDone || !transport.clientConnectedNotifier.value) {
      throw TransportUnavailableException(
        'Debes estar conectado al banco y completar el handshake.',
      );
    }
    if (_self._pendingBankOperationCompleter != null) {
      throw const BankLedgerException(
        'Ya hay una operación bancaria en proceso.',
      );
    }

    final requestId =
        '${session.name}-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<void>();
    _self._pendingBankOperationId = requestId;
    _self._pendingBankOperationCompleter = completer;
    P2PService().setTransport(TransportType.ble);
    try {
      await P2PService().sendPayload({
        'type': 'bank_operation_request',
        'requestId': requestId,
        'playerId': session.name,
        'deviceInstallationId': DeviceIdentityService.installationId,
        ...request,
      });
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'El banco no confirmó la operación. Intenta nuevamente.',
        ),
      );
    } finally {
      if (identical(_self._pendingBankOperationCompleter, completer)) {
        _self._pendingBankOperationCompleter = null;
        _self._pendingBankOperationId = null;
      }
    }
  }

  Future<void> _handleBankTransferHoldRequest(
      Map<String, dynamic> payload) async {
    final sourceTransport = _transportForIncomingPayload(payload);
    final sourcePlayerId = _connectedPlayerIdForPayload(payload);
    if (sourcePlayerId == null || !mounted) return;
    final requestId = payload['requestId'] as String?;
    if (_self._bankTransferHoldDialogOpen) {
      await _sendBankError(
        sourcePlayerId,
        'El banco ya está procesando otra transferencia.',
        transportType: sourceTransport,
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
          transportType: sourceTransport, requestId: requestId);
    } on BankLedgerException catch (error) {
      await _sendBankError(
        sourcePlayerId,
        error.message,
        transportType: sourceTransport,
        requestId: requestId,
      );
      return;
    } on TransportUnavailableException catch (_) {
      // El débito ya se realizó pero el jugador no confirmó.
      // El estado se sincronizará en el próximo handshake o reconexión.
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

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var sending = false;
        var completed = false;
        var settled = false;
        var message =
            'Acerca el celular del jugador receptor y pulsa entregar.';

        return StatefulBuilder(
          builder: (context, setDialogState) {
              Future<void> deliver() async {
                  if (sending || completed) return;
                  setDialogState(() {
                    sending = true;
                    message =
                        'Acerca el jugador receptor al banco...';
                  });

                  final transport = P2PService().bleTransport;
                  if (P2PService().currentType == TransportType.ble &&
                      transport.serverActiveNotifier.value &&
                      transport.clientConnectedNotifier.value) {
                    transport.contactReadyNotifier.value = false;
                    final current =
                        transport.connectedPlayersNotifier.value;
                    final reset = <BleConnectedPlayer>[];
                    for (final player in current) {
                      if (player.contactReady) {
                        reset.add(player.copyWith(contactReady: false));
                      } else {
                        reset.add(player);
                      }
                    }
                    transport.connectedPlayersNotifier.value = reset;

                    final contactCompleter = Completer<bool>();
                    void finish(bool v) {
                      if (contactCompleter.isCompleted) return;
                      contactCompleter.complete(v);
                    }
                    void contactListener() {
                      if (transport.contactReadyNotifier.value ||
                          transport.connectedPlayersNotifier.value.any(
                              (p) => p.subscribed && p.contactReady)) {
                        finish(true);
                      }
                    }
                    transport.contactReadyNotifier
                        .addListener(contactListener);
                    transport.connectedPlayersNotifier
                        .addListener(contactListener);
                    final timeout = Timer(
                        const Duration(seconds: 15),
                        () => finish(false));
                    contactListener();
                    final contactReady = await contactCompleter.future;
                    timeout.cancel();
                    transport.contactReadyNotifier
                        .removeListener(contactListener);
                    transport.connectedPlayersNotifier
                        .removeListener(contactListener);

                    if (!contactReady) {
                      if (ctx.mounted) {
                        setDialogState(() {
                          sending = false;
                          message =
                              'No se detectó contacto. Acerca el jugador e intenta de nuevo.';
                        });
                      }
                      return;
                    }
                    setDialogState(() {
                      message =
                          'Buscando al jugador receptor en contacto...';
                    });
                  }

                  try {
                    final isNotSource = (BleConnectedPlayer p) =>
                        p.displayName != fromName;
                var players = P2PService()
                    .bleTransport
                    .connectedPlayersNotifier
                    .value
                    .where((p) => p.subscribed && p.playing && isNotSource(p))
                    .toList();
                if (players.isEmpty) {
                  players = P2PService()
                      .bleTransport
                      .connectedPlayersNotifier
                      .value
                      .where((p) => p.subscribed && isNotSource(p))
                      .toList();
                }
                final String? receiverName =
                    players.isNotEmpty ? players.first.displayName : null;
                if (receiverName == null) {
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    sending = false;
                    message =
                        'No se detectó un jugador listo. Acércalo e intenta de nuevo.';
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
                  transportType: sourceTransport,
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
                                  transportType: sourceTransport,
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
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        title: const Text(
          'Transferencia pendiente de confirmación',
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
                'El jugador no confirmó la recepción del débito. '
                'El dinero ya fue retenido en el banco. '
                'El estado se sincronizará en la próxima reconexión.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
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
        ],
      ),
    ).whenComplete(() {
      _self._dialogActive = false;
      _self._bankTransferHoldDialogOpen = false;
    });
  }
}






