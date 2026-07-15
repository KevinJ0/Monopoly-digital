part of '../wallet_screen.dart';

mixin _WalletConnection on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;

  String? _wsBankIp;
  int _wsBankPort = 8080;
  bool _wsConnecting = false;

  void _connectToHost(SessionProvider session) {
    // no-op
  }

  void _startWsClient() {
    _self._wsScanning = true;
    if (mounted) setState(() {});
  }

  void _stopWsClient() {
    _self._wsScanning = false;
    _self._userRequestedWsDisconnect = true;
    if (mounted) setState(() {});
    P2PService().wsTransport.stop().then((_) {
      _self._userRequestedWsDisconnect = false;
      if (mounted) setState(() {});
    });
  }

  void _connectToWsBank(String host, int port) {
    _connectToBank(host, port: port);
  }

  Future<void> _reiniciarWsServer() async {
    await P2PService().wsTransport.stop();
    await P2PService().startWsServer();
  }

  void _detenerWsServer() {
    P2PService().wsTransport.stop();
  }

  Future<bool> _ensureWsReady() async {
    return P2PService().wsTransport.init();
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
        .wsTransport
        .serverActiveNotifier
        .addListener(_self._bankServerListener!);
  }

  void _listenForBankPlayerConnections() {
    final notifier = P2PService().wsTransport.connectedPlayersNotifier;
    _self._wsConnectionsListener ??= () {
      final connected = notifier.value
          .where((player) => player.connected)
          .toList(growable: false);
      final connectedIds = connected.map((player) => player.id).toSet();
      _self._announcedWsConnections.removeWhere(
        (id) => !connectedIds.contains(id),
      );

      for (final player in connected) {
        if (_self._announcedWsConnections.contains(player.id)) continue;
        _self._announcedWsConnections.add(player.id);
        debugPrint(
          '[WS bank] Jugador conectado id=${player.id} nombre=${player.displayName}',
        );
        NotificationService().show(
          '${player.displayName} se conect\u00f3 al banco',
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          dedupeKey: 'ws-connected:${player.id}',
        );
      }
    };
    notifier.addListener(_self._wsConnectionsListener!);
    _self._wsConnectionsListener!();
  }

  void _listenForWsDisconnection() {
    final notifier = P2PService().wsTransport.clientConnectedNotifier;
    _self._wasWsClientConnected = notifier.value;
    _self._wsClientConnectionListener ??= () {
      final connected = notifier.value;

      if (connected && _self._wsConnecting) {
        _self._wsConnecting = false;
        if (mounted && !_self._dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      } else if (!connected &&
          _self._wasWsClientConnected &&
          !_self._userRequestedWsDisconnect) {
        _self._wsConnecting = false;
        if (mounted && !_self._dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        Future.microtask(() {
          if (!mounted || _self._userRequestedWsDisconnect) return;
          NotificationService().show(
            'Se perdi\u00f3 la conexi\u00f3n con el banco. El servidor fue apagado o dej\u00f3 de estar disponible.',
            backgroundColor: kRed,
            duration: const Duration(seconds: 5),
            dedupeKey: 'ws-bank-disconnected',
          );
        });
      }

      _self._wasWsClientConnected = connected;
    };
    notifier.addListener(_self._wsClientConnectionListener!);
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
    // no-op for WS
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

  Future<void> _connectToBank(String host, {int port = 8080}) async {
    if (_self._wsConnecting) return;
    _self._wsConnecting = true;
    _self._wsBankIp = host;
    _wsBankPort = port;
    setState(() {});

    try {
      P2PService().setTransport(TransportType.ws);
      await P2PService().wsTransport.connectToBank(host, port: port);

      final session = context.read<SessionProvider>();
      P2PService().wsTransport.sendIdentity(
        name: session.name,
        avatarId: session.avatarId,
        colorId: session.colorId,
        deviceInstallationId: DeviceIdentityService.installationId,
      );

      _self._wsConnecting = false;
      setState(() {});
    } catch (e) {
      _self._wsConnecting = false;
      if (mounted) {
        NotificationService().show(
          'No se pudo conectar al banco en $host:$port',
          backgroundColor: kRed,
          duration: const Duration(seconds: 4),
        );
        setState(() {});
      }
    }
  }

  Future<void> _disconnectFromBank() async {
    _self._userRequestedWsDisconnect = true;
    _self._wsConnecting = false;
    try {
      await P2PService().wsTransport.stop();
      if (mounted) _self._safeSetState(() {});
    } finally {
      _self._userRequestedWsDisconnect = false;
    }
  }
}
