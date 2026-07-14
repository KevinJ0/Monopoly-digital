part of '../wallet_screen.dart';

mixin _WalletConnection on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;
  void _connectToHost(SessionProvider session) {
    // no-op
  }

  void _listenForBankServerState() {
    _self._bankServerListener ??= () {
      if (mounted && !_self._dialogActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    };
    P2PService()
        .bleTransport
        .serverActiveNotifier
        .addListener(_self._bankServerListener!);
  }

  void _listenForBankPlayerConnections() {
    final notifier = P2PService().bleTransport.connectedPlayersNotifier;
    _self._bleConnectionsListener ??= () {
      final connected = notifier.value
          .where((player) => player.subscribed)
          .toList(growable: false);
      final connectedIds = connected.map((player) => player.id).toSet();
      _self._announcedBleConnections.removeWhere(
        (deviceId) => !connectedIds.contains(deviceId),
      );

      for (final player in connected) {
        if (_self._announcedBleConnections.contains(player.id)) {
          continue;
        }
        _self._announcedBleConnections.add(player.id);
        debugPrint(
          '[BLE bank] Jugador suscrito id=${player.id} nombre=${player.displayName}',
        );
        NotificationService().show(
          '${player.displayName} se conectó al banco\n'
          'Dispositivo: ${player.displayDeviceName}',
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          dedupeKey: 'ble-connected:${player.id}',
        );
      }
    };
    notifier.addListener(_self._bleConnectionsListener!);
    _self._bleConnectionsListener!();
  }

  void _listenForBleBankDisconnection() {
    final notifier = P2PService().bleTransport.clientConnectedNotifier;
    _self._wasBleClientConnected = notifier.value;
    _self._bleClientConnectionListener ??= () {
      final connected = notifier.value;

      if (connected && _self._bleScanning) {
        _self._bleScanning = false;
        if (mounted && !_self._dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      } else if (!connected &&
          _self._wasBleClientConnected &&
          !_self._userRequestedBleDisconnect) {
        _self._bleScanning = true;
        if (mounted && !_self._dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        Future.microtask(() {
          if (!mounted || _self._userRequestedBleDisconnect) return;
          NotificationService().show(
            'Se perdi\u00f3 la conexi\u00f3n con el banco. El servidor BLE fue apagado o dej\u00f3 de estar disponible.',
            backgroundColor: kRed,
            duration: const Duration(seconds: 5),
            dedupeKey: 'ble-bank-disconnected',
          );
        });
      }

      _self._wasBleClientConnected = connected;
    };
    notifier.addListener(_self._bleClientConnectionListener!);
  }

  void _listenToBankStats() {
    final revision = BankLedgerService().statsRevision;
    _self._bankStatsListener ??= () {
      if (!mounted) return;
      final session = HiveService.sessionBox.get('current');
      if (session == null || session.role != 'banco') return;
      context.read<StatsProvider>().restore(
            volume: session.totalVolume,
            count: session.txCount,
            passGo: session.passGoCount,
          );
    };
    revision.addListener(_self._bankStatsListener!);
    _self._bankStatsListener!();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = context.read<SessionProvider>();
      if (session.isBank) {
        P2PService().bleTransport.refreshAvailability().then((_) {
          if (mounted && !_self._dialogActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        });
      }
    }
  }

  void _setBleClientIdentity() {
    final session = context.read<SessionProvider>();
    P2PService().bleTransport.setClientIdentity(
          name: session.name,
          avatarId: session.avatarId,
          colorId: session.colorId,
          isHandshakeDone: session.isHandshakeDone,
        );
  }

  void _listenToBankruptcy() {
    final wallet = context.read<WalletController>();
    _self._bankruptNotifierRef = wallet.bankruptNotifier;
    _self._bankruptListener ??= () {
      if (wallet.bankruptNotifier.value && mounted) {
        _self._openBankruptcyScreen();
      }
    };
    wallet.bankruptNotifier.addListener(_self._bankruptListener!);
    _self._bankruptListener!();

    _self._txSub?.cancel();
    _self._txSub = wallet.txStream.listen((event) {
      if (event == TxType.largeTransfer && mounted) {
        _self._confettiCtrl.play();
      }
    });
  }

  Future<void> _startBleClient() async {
    if (_self._bleScanning) return;
    final transport = P2PService().bleTransport;
    final ready = await _ensureBleReady(transport);
    if (!ready || !mounted) return;

    if (P2PService().currentType != TransportType.ble) {
      P2PService().setTransport(TransportType.ble);
    }
    _setBleClientIdentity();
    _self._bleScanning = true;
    setState(() {});
    try {
      await P2PService().startReceiving(null);
    } catch (e, s) {
      _self._bleScanning = false;
      if (mounted) _self._safeSetState(() {});
      if (mounted) _self._safeShowFriendlyError(e, s);
    }
  }

  Future<void> _stopBleClient() async {
    _self._userRequestedBleDisconnect = true;
    _self._bleScanning = false;
    try {
      await P2PService().bleTransport.stopClientScan();
      if (mounted) _self._safeSetState(() {});
    } finally {
      _self._userRequestedBleDisconnect = false;
    }
  }

  Future<void> _connectToBleBank(BleBankDevice bank) async {
    SoundService.playClick();
    _setBleClientIdentity();
    try {
      await P2PService().bleTransport.connectToBank(bank);
    } catch (e, s) {
      if (mounted) _self._safeShowFriendlyError(e, s);
    }
  }

  Future<bool> _ensureBleReady(BleTransport transport) async {
    var status = await transport.refreshAvailability();
    if (status == BleAvailabilityStatus.ready) return true;
    if (!mounted) return false;

    if (status == BleAvailabilityStatus.noHardware) {
      _self._showToast('Este dispositivo no tiene Bluetooth LE disponible.', kRed);
      return false;
    }

    if (status == BleAvailabilityStatus.missingPermissions) {
      final allow = await _self._confirmAction(
        title: 'Permisos de Bluetooth',
        message:
            'Para usar la conexión BLE necesito permisos de Bluetooth. ¿Quieres permitirlos ahora?',
        confirmLabel: 'Permitir',
      );
      if (allow != true || !mounted) return false;

      await transport.requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));
      status = await transport.refreshAvailability();
      if (status == BleAvailabilityStatus.ready) return true;
      if (status == BleAvailabilityStatus.bluetoothOff) {
        return _askToOpenBleSettings(transport);
      }
      _self._showToast(
          'Permisos de Bluetooth pendientes. Revisa los permisos de la app.',
          kRed);
      return false;
    }

    if (status == BleAvailabilityStatus.bluetoothOff) {
      return _askToOpenBleSettings(transport);
    }

    _self._showToast(
        'No pude verificar Bluetooth. Revisa los ajustes e intenta de nuevo.',
        kRed);
    return false;
  }

  Future<bool> _askToOpenBleSettings(BleTransport transport) async {
    final open = await _self._confirmAction(
      title: 'Bluetooth apagado',
      message:
          'Para conectarte por BLE debes activar Bluetooth. ¿Quieres abrir los ajustes para encenderlo?',
      confirmLabel: 'Abrir ajustes',
    );
    if (open == true && mounted) {
      await transport.openBleSettings();
    }
    return false;
  }

  Future<void> _reiniciarBleBanco() async {
    final transport = P2PService().bleTransport;
    try {
      await transport.stopServer();
    } catch (_) {}
    transport.connectedPlayersNotifier.value = const [];
    await transport.resetState();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final ready = await _ensureBleReady(transport);
    if (!ready || !mounted) return;
    await P2PService().startBleBankServer();
    P2PService().setTransport(TransportType.ble);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _detenerBleBanco() async {
    final transport = P2PService().bleTransport;
    try {
      await transport.stopServer();
    } catch (_) {}
    transport.connectedPlayersNotifier.value = const [];
    if (mounted) {
      setState(() {});
    }
  }
}






