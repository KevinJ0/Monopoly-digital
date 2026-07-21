part of '../wallet_screen.dart';

mixin _WalletConnection on State<WalletScreen> {
  _WalletScreenState get _self => this as _WalletScreenState;

  void _connectToHost(SessionProvider session) {
    // no-op for bank
  }

  Future<void> _reiniciarWsServer() async {
    await P2PService().wsTransport.stop();
    await P2PService().startWsServer();
  }

  void _detenerWsServer() {
    P2PService().wsTransport.stop();
  }

  Future<bool> _ensureWsReady() async {
    try {
      await P2PService().wsTransport.initialize();
      return true;
    } catch (_) {
      return false;
    }
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

  void _listenToBankruptcy() {
    final wallet = context.read<WalletController>();
    _self._bankruptNotifierRef = wallet.bankruptNotifier;
    _self._bankruptListener ??= () {
      if (wallet.bankruptNotifier.value && mounted) {
        if (!_self._bankruptcyScreenOpen) {
          _self._openBankruptcyScreen();
        }
      }
    };
    wallet.bankruptNotifier.addListener(_self._bankruptListener!);
    final session = context.read<SessionProvider>();
    if (!session.isHandshakeDone) {
      _self._bankruptListener!();
    }

    _self._txSub?.cancel();
    _self._txSub = wallet.txStream.listen((event) {
      if (event == TxType.largeTransfer && mounted) {
        _self._confettiCtrl.play();
      }
    });
  }
}
