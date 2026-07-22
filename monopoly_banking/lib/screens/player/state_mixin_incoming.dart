part of '../player_screen.dart';

mixin _PlayerIncoming on State<PlayerScreen> {
  _PlayerScreenState get _self => this as _PlayerScreenState;

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

      if (type == 'bank_server_stopping') {
        _self._userRequestedWsDisconnect = true;
        try {
          await P2PService().wsTransport.stop();
        } finally {
          _self._userRequestedWsDisconnect = false;
        }
        if (mounted) {
          _self._safeSetState(() {});
          NotificationService().show(
            'El banco apag\u00f3 el servidor. Has sido desconectado.',
            backgroundColor: kRed,
            duration: const Duration(seconds: 5),
            dedupeKey: 'ws-bank-disconnected',
          );
        }
        return;
      }

      if (type == 'handshake' ||
          type == 'bank_state' ||
          type == 'bank_operation_error' ||
          type == 'bank_access_denied') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        final changed = await session.adoptBankSession(
          payload['bankSessionId'] as String?,
        );
        if (changed) {
          _self._setClientIdentity();
          NotificationService().show(
            'El banco termin\u00f3 la partida anterior. Se inici\u00f3 una nueva partida.',
            backgroundColor: kGold,
            duration: const Duration(seconds: 5),
          );
          if (type != 'handshake') return;
        }
      }

      if (type == 'handshake') {
        debugPrint('[PLAYER] Handshake received target=${payload['targetPlayerId']} myName=${session.name} balance=${payload['balance']} isHandshakeDone=${session.isHandshakeDone}');
        if (!_isPayloadForPlayer(payload, session.name)) {
          debugPrint('[PLAYER] Handshake NOT for me, skipping');
          return;
        }
        try {
          if (!session.isHandshakeDone) {
            await session.applyHandshake(payload);
            _self._setClientIdentity();
            _self._triggerWelcomeAnimation(payload['name'] as String?);
          }
          await wallet.applyBankState(payload);
          debugPrint('[PLAYER] after applyBankState wallet.balance=${wallet.balance} rawBalance=${wallet.rawBalance.value}');
        } catch (e) {
          debugPrint('[PLAYER] HANDSHAKE ERROR: $e');
        }
        try {
          await WidgetsBinding.instance.endOfFrame
              .timeout(const Duration(seconds: 1));
        } on TimeoutException {}
        try {
          await P2PService().sendPayload({
            'type': 'handshake_confirm',
            if (payload['bankTxId'] != null) 'bankTxId': payload['bankTxId'],
            'playerId': session.name,
            'name': session.name,
            'appliedBalance': wallet.balance,
            'deviceInstallationId': DeviceIdentityService.installationId,
          });
        } on TransportUnavailableException {}
      } else if (type == 'bank_state') {
        debugPrint('[PLAYER] bank_state received isHandshakeDone=${session.isHandshakeDone} targetPlayerId=${payload['targetPlayerId']} myName=${session.name} balance=${payload['balance']}');
        if (!session.isHandshakeDone) {
          debugPrint('[PLAYER] bank_state SKIPPED: isHandshakeDone=false');
          return;
        }
        if (!_isPayloadForPlayer(payload, session.name)) {
          debugPrint('[PLAYER] bank_state SKIPPED: not for me');
          return;
        }
        await wallet.applyBankState(payload);
        debugPrint('[PLAYER] applyBankState done balance=${wallet.balance} rawBalance=${wallet.rawBalance.value}');
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null && bankTxId.isNotEmpty) {
          try {
            await WidgetsBinding.instance.endOfFrame
                .timeout(const Duration(seconds: 1));
          } on TimeoutException {}
          try {
            await P2PService().sendPayload({
              'type': 'bank_state_ack',
              'bankTxId': bankTxId,
              'playerId': session.name,
              'name': session.name,
              'appliedBalance': wallet.balance,
              'deviceInstallationId': DeviceIdentityService.installationId,
            });
            debugPrint('[PLAYER] bank_state_ack sent for bankTxId=$bankTxId');
          } on TransportUnavailableException {
            debugPrint('[PLAYER] bank_state_ack failed: transport unavailable');
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
            requestId.startsWith('transfer-')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              NotificationService().show(
                'Transferencia enviada al banco.',
                backgroundColor: kGreen,
                duration: const Duration(seconds: 3),
              );
            }
          });
        }
      } else if (type == 'bank_operation_error') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        final message =
            (payload['message'] as String?) ?? 'El banco rechaz\u00f3 la operaci\u00f3n.';
        final requestId = payload['requestId'] as String?;
        if (requestId == _self._pendingBankOperationId) {
          final completer = _self._pendingBankOperationCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.completeError(BankLedgerException(message));
          }
        } else if (requestId != null &&
            requestId.startsWith('transfer-')) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationService().show(
                message,
                backgroundColor: kRed,
                duration: const Duration(seconds: 4),
              );
            });
          }
        } else {
          await _showBankOperationError(message);
        }
      } else if (type == 'bank_access_denied') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        _self._stopWsClient();
        await wallet.applyBankState(payload);
      } else if (type == 'kick') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        if (!_self._hasBeenKicked) {
          _self._hasBeenKicked = true;
          HapticFeedback.heavyImpact();
        }
        _self._userRequestedWsDisconnect = true;
        await P2PService().wsTransport.stop();
        if (!mounted) return;
        _self._safeSetState(() {});
        Navigator.of(context).push(
          GameFadeRoute(
            page: KickedScreen(playerName: session.name),
          ),
        );
      } else if (type == 'new_player') {
        debugPrint('[PLAYER] new_player received, showing onboarding');
        final result = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
        if (result == null || !mounted) {
          debugPrint('[PLAYER] new_player onboarding cancelled, disconnecting');
          _self._stopWsClient();
          return;
        }
        final newName = result['name'] as String;
        final newAvatarId = result['avatarEmoji'] as String;
        final newColorId = (result['colorIndex'] as int).toString();
        await session.updateProfile(
          name: newName,
          avatarId: newAvatarId,
          colorId: newColorId,
        );
        await P2PService().sendPayload({
          'type': 'player_profile',
          'name': newName,
          'avatarId': newAvatarId,
          'colorId': newColorId,
          'deviceInstallationId': DeviceIdentityService.installationId,
        });
      }
    }, onError: (e, s) {
      if (mounted) _self._safeShowFriendlyError(e, s);
    });
  }

  bool _isPayloadForPlayer(Map<String, dynamic> payload, String playerId) {
    if (playerId.isEmpty) return true;
    final target = payload['targetPlayerId'] as String?;
    return target == null || target == playerId;
  }

  void _setClientIdentity() {
    final session = context.read<SessionProvider>();
    P2PService().wsTransport.sendIdentity(
      name: session.name,
      avatarId: session.avatarId,
      colorId: session.colorId,
      deviceInstallationId: DeviceIdentityService.installationId,
      isHandshakeDone: session.isHandshakeDone,
    );
  }

  Future<void> _requestBankOperation(Map<String, dynamic> request) async {
    final session = context.read<SessionProvider>();
    if (!session.isHandshakeDone) {
      throw TransportUnavailableException(
        'Debes estar conectado al banco y completar el handshake.',
      );
    }
    if (_self._pendingBankOperationCompleter != null) {
      throw const BankLedgerException(
        'Ya hay una operaci\u00f3n bancaria en proceso.',
      );
    }

    final requestId =
        '${session.name}-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<void>();
    _self._pendingBankOperationId = requestId;
    _self._pendingBankOperationCompleter = completer;
    P2PService().setTransport(TransportType.ws);
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
          'El banco no confirm\u00f3 la operaci\u00f3n. Intenta nuevamente.',
        ),
      );
    } finally {
      if (identical(_self._pendingBankOperationCompleter, completer)) {
        _self._pendingBankOperationCompleter = null;
        _self._pendingBankOperationId = null;
      }
    }
  }

  Future<void> _showBankOperationError(String message) async {
    if (!mounted) return;
    await showGameDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Operaci\u00f3n rechazada'),
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
}
