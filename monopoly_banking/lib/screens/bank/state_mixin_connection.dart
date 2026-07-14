part of '../bank_screen.dart';

mixin _BankConnection on State<BankScreen> {
  _BankScreenState get _self => this as _BankScreenState;

  void didChangeAppLifecycleState(AppLifecycleState state) {
    // no-op
  }

  Future<bool> _waitForBlePlayerReady(
      _BankOperationDialogController dialog) async {
    final notifier = P2PService().bleTransport.connectedPlayersNotifier;

    bool hasReadyPlayer() => notifier.value.any(
          (player) =>
              player.subscribed &&
              player.name.trim().isNotEmpty &&
              player.deviceInstallationId.trim().isNotEmpty,
        );

    if (hasReadyPlayer()) return true;

    dialog.update(
      title: 'Preparando conexión',
      message: 'Esperando que el jugador complete el canal BLE...',
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

  Future<bool> _waitForBleContactIfNeeded(
      _BankOperationDialogController dialog) async {
    if (dialog.transportType != TransportType.ble) return true;
    final transport = P2PService().bleTransport;
    if (!transport.serverActiveNotifier.value ||
        !transport.clientConnectedNotifier.value) {
      return true;
    }

    transport.contactReadyNotifier.value = false;
    transport.contactRssiNotifier.value = null;

    final current = transport.connectedPlayersNotifier.value;
    final reset = <BleConnectedPlayer>[];
    for (final player in current) {
      if (player.contactReady) {
        reset.add(player.copyWith(contactReady: false));
      } else {
        reset.add(player);
      }
    }
    transport.connectedPlayersNotifier.value = reset;

    final completer = Completer<bool>();
    dialog.update(
      title: 'Acerca el jugador al banco',
      message: 'Acerca los dispositivos para ejecutar esta operación.',
    );

    void finish(bool value) {
      if (completer.isCompleted) return;
      completer.complete(value);
    }

    void contactListener() {
      if (_hasBleContact(transport)) {
        finish(true);
      }
    }

    transport.contactReadyNotifier.addListener(contactListener);
    transport.connectedPlayersNotifier.addListener(contactListener);
    void cancelListener() {
      if (dialog.cancelled.value) finish(false);
    }

    dialog.cancelled.addListener(cancelListener);

    void rssiListener() {
      final rssi =
          _closestBleRssi(transport) ?? transport.contactRssiNotifier.value;
      if (rssi == null) return;
      dialog.update(
        title: 'Acerca el jugador al banco',
        message: 'Señal actual: $rssi dBm. Acerca más los dispositivos.',
      );
    }

    void debugRssiListener() {
      if (!kDebugMode) return;
      final players = transport.connectedPlayersNotifier.value;
      final lines = <String>[
        'contactReady: ${transport.contactReadyNotifier.value}',
        'contactRssi: ${transport.contactRssiNotifier.value}',
      ];
      for (final p in players) {
        lines.add(
          '${p.displayName} | rssi: ${p.rssi} | contact: ${p.contactReady} | sub: ${p.subscribed}',
        );
      }
      dialog.debugInfo.value = lines.join('\n');
    }

    transport.contactRssiNotifier.addListener(rssiListener);
    transport.connectedPlayersNotifier.addListener(rssiListener);
    transport.contactRssiNotifier.addListener(debugRssiListener);
    transport.connectedPlayersNotifier.addListener(debugRssiListener);
    contactListener();
    rssiListener();
    debugRssiListener();

    final timeout = Timer(const Duration(seconds: 15), () => finish(false));

    final result = await completer.future;
    timeout.cancel();
    transport.contactReadyNotifier.removeListener(contactListener);
    transport.connectedPlayersNotifier.removeListener(contactListener);
    transport.contactRssiNotifier.removeListener(rssiListener);
    transport.connectedPlayersNotifier.removeListener(rssiListener);
    transport.contactRssiNotifier.removeListener(debugRssiListener);
    transport.connectedPlayersNotifier.removeListener(debugRssiListener);
    dialog.cancelled.removeListener(cancelListener);
    return result;
  }

  BleConnectedPlayer? _contactPlayer() {
    final players = P2PService().bleTransport.connectedPlayersNotifier.value;
    final inContact = players
        .where((player) => player.subscribed && player.contactReady)
        .toList();
    if (inContact.isEmpty) return null;
    inContact.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return inContact.first;
  }

  bool _hasBleContact(BleTransport transport) {
    if (transport.contactReadyNotifier.value) return true;
    return transport.connectedPlayersNotifier.value.any(
      (player) => player.subscribed && player.contactReady,
    );
  }

  int? _closestBleRssi(BleTransport transport) {
    final values = transport.connectedPlayersNotifier.value
        .where((player) => player.subscribed && player.rssi != null)
        .map((player) => player.rssi!)
        .toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => b.compareTo(a));
    return values.first;
  }

  Future<BleConnectedPlayer?> _waitForTransferReceiver() async {
    final transport = P2PService().bleTransport;
    final current = _currentTransferReceiver(transport);
    if (current != null) return current;

    final completer = Completer<BleConnectedPlayer?>();
    Timer? timeout;
    late VoidCallback listener;

    void finish(BleConnectedPlayer? player) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      transport.connectedPlayersNotifier.removeListener(listener);
      completer.complete(player);
    }

    listener = () {
      final player = _currentTransferReceiver(transport);
      if (player != null) finish(player);
    };

    transport.connectedPlayersNotifier.addListener(listener);
    timeout = Timer(const Duration(seconds: 15), () => finish(null));
    return completer.future;
  }

  BleConnectedPlayer? _currentTransferReceiver(BleTransport transport) {
    for (final player in transport.connectedPlayersNotifier.value) {
      if (player.subscribed && player.playing) {
        return player;
      }
    }
    for (final player in transport.connectedPlayersNotifier.value) {
      if (player.subscribed) return player;
    }
    return null;
  }

  Future<void> _sendToConnectedPlayer(Map<String, dynamic> payload) async {
    final payloadType = payload['type'];
    final playerId = payload['targetPlayerId'];
    AppAuditLogger.instance.event('BANK_OP', 'send_to_player',
        data: {'type': payloadType, 'playerId': playerId});
    final transport = P2PService().bleTransport;
    P2PService().setTransport(TransportType.ble);

    if (!transport.serverActiveNotifier.value) {
      throw TransportUnavailableException(
        'Servidor BLE apagado. Vuelve a la pantalla principal del banco para activarlo.',
      );
    }

    if (!transport.clientConnectedNotifier.value) {
      throw TransportUnavailableException(
        'No hay jugador conectado por BLE. Abre la app del jugador y conéctalo al banco.',
      );
    }

    if (!_hasBleContact(transport)) {
      final rssi =
          _closestBleRssi(transport) ?? transport.contactRssiNotifier.value;
      AppAuditLogger.instance.event('BANK_OP', 'no_ble_contact',
          data: {'rssi': rssi, 'contactReady': transport.contactReadyNotifier.value});
      throw TransportUnavailableException(
        rssi == null
            ? 'No se recibió señal de proximidad BLE. Acerca los dispositivos y mantenlos juntos.'
            : 'Jugador fuera de contacto BLE ($rssi dBm). Acerca los dispositivos.',
      );
    }

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

  String _playerNameLabel() {
    final knownName = _self._connectedPlayerName.trim();
    if (knownName.isNotEmpty && knownName != 'Jugador') return knownName;
    final name = P2PService().bleTransport.connectedDeviceNameNotifier.value;
    return name.trim().isEmpty ? 'Jugador' : name;
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
  }
}
