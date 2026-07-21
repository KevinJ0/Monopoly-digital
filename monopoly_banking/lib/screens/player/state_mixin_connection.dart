part of '../player_screen.dart';

mixin _PlayerConnection on State<PlayerScreen> {
  _PlayerScreenState get _self => this as _PlayerScreenState;

  String? _wsBankIp;
  int _wsBankPort = 8080;
  bool _wsConnecting = false;

  void _startWsClient() {
    _self._wsScanning = true;
    if (mounted) setState(() {});
    P2PService().wsTransport.startDiscovery(isBank: false);
  }

  void _stopWsClient() {
    _self._wsScanning = false;
    _self._wsConnecting = false;
    _self._userRequestedWsDisconnect = true;
    if (mounted) setState(() {});
    P2PService().wsTransport.stopDiscovery();
    P2PService().wsTransport.stop().then((_) {
      _self._userRequestedWsDisconnect = false;
    });
  }

  void _connectToWsBank(String host, int port) {
    _connectToBank(host, port: port);
  }

  void _listenForWsDisconnection() {
    final notifier = P2PService().wsTransport.clientConnectedNotifier;
    _self._wsClientConnectionListener ??= () {
      final connected = notifier.value;

      if (connected) {
        if (_self._inReconnectionGrace) {
          _self._inReconnectionGrace = false;
          _self._reconnectionTimer?.cancel();
          _self._reconnectionTimer = null;
        }
        _self._wsScanning = false;
        P2PService().wsTransport.stopDiscovery();
        if (_self._wsConnecting) {
          _self._wsConnecting = false;
        }
        if (mounted && !_self._dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      } else if (!_self._userRequestedWsDisconnect) {
        if (_self._inReconnectionGrace) return;
        _self._inReconnectionGrace = true;
        _self._reconnectionTimer?.cancel();
        _self._reconnectionTimer = Timer(const Duration(seconds: 6), () {
          _self._inReconnectionGrace = false;
          _self._reconnectionTimer = null;
          _self._wsConnecting = false;
          _startWsClient();
          if (mounted) {
            NotificationService().show(
              'Se perdi\u00f3 la conexi\u00f3n con el banco. Intentando reconectar...',
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              dedupeKey: 'ws-bank-disconnected',
            );
            setState(() {});
          }
        });
        if (mounted) {
          NotificationService().show(
            'Conexi\u00f3n perdida. Reconectando en 6 segundos...',
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
            dedupeKey: 'ws-reconnecting',
          );
          setState(() {});
        }
      }
    };
    notifier.addListener(_self._wsClientConnectionListener!);
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

  Future<void> _connectToBank(String host, {int port = 8080}) async {
    if (_self._wsConnecting) return;
    if (P2PService().wsTransport.clientConnectedNotifier.value) {
      debugPrint('[PLAYER] CONNECT WS already connected, closing client first');
      await P2PService().wsTransport.closeClient();
    }
    _self._wsConnecting = true;
    _self._wsBankIp = host;
    _wsBankPort = port;
    setState(() {});

    try {
      P2PService().setTransport(TransportType.ws);
      await P2PService().wsTransport.connectToBank(host, port: port);

      if (!mounted) return;
      final session = context.read<SessionProvider>();

      P2PService().wsTransport.sendIdentity(
        name: session.name,
        avatarId: session.avatarId,
        colorId: session.colorId,
        deviceInstallationId: DeviceIdentityService.installationId,
        isHandshakeDone: session.isHandshakeDone,
      );

      _self._wsConnecting = false;
      if (mounted) setState(() {});
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
