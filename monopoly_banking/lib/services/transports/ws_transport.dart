import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/ws_models.dart';

class WsTransport extends P2PTransport {
  @override
  String get name => 'WiFi Direct';

  @override
  IconData get icon => Icons.wifi_rounded;

  @override
  String get description => 'Conexi\u00f3n directa por WiFi';

  @override
  bool get isEnabled => true;

  static const int defaultPort = 8080;

  HttpServer? _server;
  WebSocket? _clientSocket;
  bool _isBank = false;
  bool _isReceiving = false;

  final _connections = <String, WebSocket>{};
  final _connectionsByInstallationId = <String, String>{};

  // Grace period para reconexión: 6 segundos
  static const Duration reconnectionGracePeriod = Duration(seconds: 6);
  // Información temporal de jugadores desconectados durante el período de gracia
  final _disconnectedPlayers = <String, WsPlayer>{};
  // Timers pendientes para eliminar jugadores desconectados
  final _pendingReconnectionTimers = <String, Timer>{};

  final _connectedPlayersCtrl =
      ValueNotifier<List<WsPlayer>>(const []);
  ValueNotifier<List<WsPlayer>> get connectedPlayersNotifier =>
      _connectedPlayersCtrl;

  // UDP Discovery
  static const int discoveryPort = 42424;
  static const String _discoveryRequest = 'monopoly_discover';
  static const String _discoveryResponse = 'monopoly_bank';

  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _discoverySub;
  bool _isDiscovering = false;
  Timer? _discoveryTimer;

  final _discoveredBanksCtrl =
      ValueNotifier<List<DiscoveredBank>>(const []);
  ValueNotifier<List<DiscoveredBank>> get discoveredBanksNotifier =>
      _discoveredBanksCtrl;
  final _bankLastSeen = <String, DateTime>{};

  final _clientConnectedCtrl = ValueNotifier<bool>(false);
  ValueNotifier<bool> get clientConnectedNotifier => _clientConnectedCtrl;

  final _connectionStatusCtrl = ValueNotifier<String>('');
  ValueNotifier<String> get connectionStatusNotifier => _connectionStatusCtrl;

  final _serverActiveCtrl = ValueNotifier<bool>(false);
  ValueNotifier<bool> get serverActiveNotifier => _serverActiveCtrl;

  String? _localIp;
  int _port = 0;

  String? get localIp => _localIp;
  int get port => _port;

  String? lastKnownIp;
  int lastKnownPort = defaultPort;

  void Function(Map<String, dynamic>)? _onData;
  StreamSubscription<dynamic>? _serverSub;
  StreamSubscription<dynamic>? _clientSub;
  final Set<StreamSubscription<dynamic>> _clientSubs = {};

  void setBankMode(bool isBank) {
    _isBank = isBank;
  }

  Future<String?> findLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('WsTransport findLocalIp error: $e');
    }
    return null;
  }

  @override
  Future<void> initialize() async {
    _localIp = await findLocalIp();
  }

  @override
  Future<void> startReceiving(
      void Function(Map<String, dynamic>) onData) async {
    if (_isReceiving) return;
    _isReceiving = true;
    _onData = onData;

    if (_isBank) {
      await _startServer();
    }
  }

  Future<void> _startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, defaultPort);
      _port = _server!.port;
      _serverActiveCtrl.value = true;
      _connectionStatusCtrl.value = 'Servidor activo en puerto $_port';

      unawaited(startDiscovery(isBank: true));

      _serverSub = _server!.listen((HttpRequest request) {
        if (request.uri.path == '/') {
          final address =
              request.connectionInfo?.remoteAddress.address ?? '';
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _handleClientConnection(socket, address);
          }).catchError((e) {
            debugPrint('WsTransport WebSocket upgrade error: $e');
          });
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });
    } catch (e) {
      _isReceiving = false;
      _serverActiveCtrl.value = false;
      _connectionStatusCtrl.value = 'Error al iniciar servidor';
      rethrow;
    }
  }

  void _handleClientConnection(WebSocket socket, String address) {
    final playerId = 'ws-${DateTime.now().microsecondsSinceEpoch}';
    String effectivePlayerId = playerId; // Se actualizará si es reconexión
    
    final sub = socket.listen(
      (data) {
        if (data is! String) {
          debugPrint('WsTransport: non-string data received, ignoring');
          return;
        }
        try {
          final decoded = jsonDecode(data) as Map<String, dynamic>;
          decoded['_wsPlayerId'] = playerId;

          if (decoded['type'] == 'ws_identity') {
            final name = decoded['name'] as String? ?? '';
            final avatarId = decoded['avatarId'] as String? ?? '';
            final colorId = decoded['colorId'] as String? ?? '0';
            final installationId =
                decoded['deviceInstallationId'] as String? ?? '';

            // Verificar si es una reconexión de un jugador en período de gracia
            String restoredPlayerId = playerId;
            bool isReconnection = false;

            if (installationId.isNotEmpty) {
              // Si ya hay una conexión ACTIVA para este dispositivo (race condition:
              // el onDone del socket anterior aún no se ha procesado), reemplazarla
              final activeId = _connectionsByInstallationId[installationId];
              if (activeId != null && activeId != playerId) {
                debugPrint(
                  'WsTransport: Reemplazando conexión activa para $installationId ($activeId)',
                );
                _pendingReconnectionTimers[activeId]?.cancel();
                _pendingReconnectionTimers.remove(activeId);
                _disconnectedPlayers.remove(activeId);
                _connections.remove(activeId);
                final list = List<WsPlayer>.from(_connectedPlayersCtrl.value);
                list.removeWhere((p) => p.id == activeId);
                _connectedPlayersCtrl.value = list;
              }

              // Buscar si hay un jugador desconectado con el mismo installationId (período de gracia)
              final disconnectedPlayer = _disconnectedPlayers.values
                  .where((p) => p.deviceInstallationId == installationId)
                  .firstOrNull;

              if (disconnectedPlayer != null) {
                // Es una reconexión - restaurar el playerId original
                restoredPlayerId = disconnectedPlayer.id;
                isReconnection = true;

                // Cancelar el timer de eliminación
                _pendingReconnectionTimers[restoredPlayerId]?.cancel();
                _pendingReconnectionTimers.remove(restoredPlayerId);

                // Eliminar el registro antiguo de desconectado
                _disconnectedPlayers.remove(restoredPlayerId);

                debugPrint(
                  'WsTransport: Reconexión detectada para jugador '
                  '$restoredPlayerId ($name)',
                );
              }
            }
            
            effectivePlayerId = restoredPlayerId;

            _connections[restoredPlayerId] = socket;
            if (installationId.isNotEmpty) {
              _connectionsByInstallationId[installationId] = restoredPlayerId;
            }

            final existing = _connectedPlayersCtrl.value.indexWhere(
                (p) => p.id == restoredPlayerId);
            final player = WsPlayer(
              id: restoredPlayerId,
              name: name,
              avatarId: avatarId,
              colorId: colorId,
              deviceInstallationId: installationId,
              address: address,
              connected: true,
              playing: true,
            );

            final list = List<WsPlayer>.from(_connectedPlayersCtrl.value);
            if (existing >= 0) {
              list[existing] = player;
            } else {
              list.add(player);
            }
            _connectedPlayersCtrl.value = list;

            // Si es reconexión, enviar evento especial
            if (isReconnection) {
              decoded['_isReconnection'] = true;
              decoded['_originalPlayerId'] = restoredPlayerId;
            }
          }

          _onData?.call(decoded);
        } catch (e) {
          debugPrint('WsTransport json decode error: $e');
        }
      },
      onDone: () {
        _removeClient(effectivePlayerId);
      },
      onError: (e) {
        debugPrint('WsTransport client error: $e');
        _removeClient(effectivePlayerId);
      },
    );
    _clientSubs.add(sub);
  }

  void updatePlayerIdentity({
    required String deviceInstallationId,
    required String name,
    required String avatarId,
    required String colorId,
  }) {
    final playerId = _connectionsByInstallationId[deviceInstallationId];
    if (playerId == null) return;
    final existing = _connectedPlayersCtrl.value.indexWhere(
        (p) => p.id == playerId);
    if (existing < 0) return;
    final list = List<WsPlayer>.from(_connectedPlayersCtrl.value);
    list[existing] = WsPlayer(
      id: playerId,
      name: name,
      avatarId: avatarId,
      colorId: colorId,
      deviceInstallationId: deviceInstallationId,
      address: list[existing].address,
      connected: true,
      playing: true,
    );
    _connectedPlayersCtrl.value = list;
  }

  void _removeClient(String playerId) {
    final sub = _clientSubs.firstWhere(
      (_) => true,
      orElse: () => Stream.empty().listen((_) {}),
    );
    _clientSubs.remove(sub);
    _connections.remove(playerId);

    // Buscar el jugador por playerId o por installationId (para reconexiones)
    var playerIndex = _connectedPlayersCtrl.value
        .indexWhere((p) => p.id == playerId);
    
    // Si no se encuentra por playerId, buscar por installationId
    if (playerIndex < 0) {
      final installationId = _connectionsByInstallationId.entries
          .where((e) => e.value == playerId)
          .map((e) => e.key)
          .firstOrNull;
      
      if (installationId != null) {
        playerIndex = _connectedPlayersCtrl.value
            .indexWhere((p) => p.deviceInstallationId == installationId);
        
        // Si se encontró por installationId, usar ese playerId
        if (playerIndex >= 0) {
          playerId = _connectedPlayersCtrl.value[playerIndex].id;
        }
      }
    }

    if (playerIndex >= 0) {
      final player = _connectedPlayersCtrl.value[playerIndex];
      // Guardar el jugador como desconectado durante el período de gracia
      _disconnectedPlayers[playerId] = player;
      _connectionsByInstallationId[player.deviceInstallationId] = playerId;

      // Iniciar timer para eliminar al jugador después de 6 segundos
      _pendingReconnectionTimers[playerId]?.cancel();
      _pendingReconnectionTimers[playerId] = Timer(
        reconnectionGracePeriod,
        () {
          _finalizeDisconnection(playerId);
        },
      );

      // Notificar que el jugador está temporalmente desconectado (no eliminar de la lista aún)
      final list = List<WsPlayer>.from(_connectedPlayersCtrl.value);
      list[playerIndex] = WsPlayer(
        id: player.id,
        name: player.name,
        avatarId: player.avatarId,
        colorId: player.colorId,
        deviceInstallationId: player.deviceInstallationId,
        address: player.address,
        connected: false, // Marcar como desconectado
        playing: player.playing,
      );
      _connectedPlayersCtrl.value = list;
    }
  }

  void _finalizeDisconnection(String playerId) {
    // Eliminar al jugador después del período de gracia
    _pendingReconnectionTimers.remove(playerId);
    _disconnectedPlayers.remove(playerId);
    _connectionsByInstallationId.removeWhere((_, id) => id == playerId);

    final list = List<WsPlayer>.from(_connectedPlayersCtrl.value);
    list.removeWhere((p) => p.id == playerId);
    _connectedPlayersCtrl.value = list;

    debugPrint('WsTransport: Jugador $playerId eliminado tras período de gracia');
  }

  Future<void> connectToBank(String host, {int port = defaultPort}) async {
    try {
      _connectionStatusCtrl.value = 'Conectando a $host:$port...';
      _clientSocket = await WebSocket.connect('ws://$host:$port');
      _clientConnectedCtrl.value = true;
      _connectionStatusCtrl.value = 'Conectado';

      _clientSub = _clientSocket!.listen(
        (data) {
          if (data is! String) {
            debugPrint('WsTransport client: non-string data received');
            return;
          }
          try {
            final decoded = jsonDecode(data) as Map<String, dynamic>;
            _onData?.call(decoded);
          } catch (e) {
            debugPrint('WsTransport client json decode error: $e');
          }
        },
        onDone: () {
          _clientConnectedCtrl.value = false;
          _connectionStatusCtrl.value = 'Desconectado';
          _clientSocket = null;
          _clientSub = null;
        },
        onError: (e) {
          debugPrint('WsTransport client connection error: $e');
          _clientConnectedCtrl.value = false;
          _connectionStatusCtrl.value = 'Error de conexión';
          _clientSocket = null;
          _clientSub = null;
        },
      );
    } catch (e) {
      _clientConnectedCtrl.value = false;
      _connectionStatusCtrl.value = 'Error al conectar';
      rethrow;
    }
  }

  void sendIdentity({
    required String name,
    required String avatarId,
    required String colorId,
    required String deviceInstallationId,
    bool isHandshakeDone = false,
  }) {
    if (_clientSocket != null) {
      _clientSocket!.add(jsonEncode({
        'type': 'ws_identity',
        'name': name,
        'avatarId': avatarId,
        'colorId': colorId,
        'deviceInstallationId': deviceInstallationId,
        'isHandshakeDone': isHandshakeDone,
      }));
    }
  }

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    if (_isBank) {
      await _sendAsBank(payload);
    } else {
      await _sendAsClient(payload);
    }
  }

  Future<void> _sendAsBank(Map<String, dynamic> payload) async {
    final targetInstallationId = payload['targetInstallationId'] as String?;

    if (targetInstallationId != null && targetInstallationId.isNotEmpty) {
      final playerId = _connectionsByInstallationId[targetInstallationId];
      if (playerId != null) {
        final socket = _connections[playerId];
        if (socket != null) {
          socket.add(jsonEncode(payload));
          return;
        }
      }
      final playerName = payload['targetPlayerId'] as String? ?? targetInstallationId;
      throw TransportUnavailableException(
        'Jugador $playerName no está conectado',
      );
    }

    // Fallback: lookup por nombre (legacy)
    final targetPlayerId = payload['targetPlayerId'] as String?;
    if (targetPlayerId != null && targetPlayerId.isNotEmpty) {
      final player = _connectedPlayersCtrl.value.where(
        (p) => p.name == targetPlayerId,
      ).firstOrNull;
      if (player != null) {
        final socket = _connections[player.id];
        if (socket != null) {
          socket.add(jsonEncode(payload));
          return;
        }
      }
      throw TransportUnavailableException(
        'Jugador $targetPlayerId no está conectado',
      );
    }

    final msg = jsonEncode(payload);
    for (final socket in _connections.values) {
      socket.add(msg);
    }
  }

  Future<void> _sendAsClient(Map<String, dynamic> payload) async {
    if (_clientSocket == null) {
      throw TransportUnavailableException(
        'No hay conexi\u00f3n con el banco',
      );
    }
    _clientSocket!.add(jsonEncode(payload));
  }

  Future<void> closeClient() async {
    _clientSub?.cancel();
    _clientSub = null;
    if (_clientSocket != null) {
      try {
        _clientSocket!.close();
      } catch (_) {}
      _clientSocket = null;
    }
    _clientConnectedCtrl.value = false;
    _connectionStatusCtrl.value = '';
  }

  @override
  Future<void> stop() async {
    _isReceiving = false;
    stopDiscovery();
    _serverSub?.cancel();
    _serverSub = null;

    for (final sub in _clientSubs) {
      sub.cancel();
    }
    _clientSubs.clear();

    for (final socket in _connections.values) {
      try {
        socket.close();
      } catch (e) {
        debugPrint('WsTransport socket close error: $e');
      }
    }
    _connections.clear();
    _connectionsByInstallationId.clear();

    // Limpiar timers de reconexión pendientes
    for (final timer in _pendingReconnectionTimers.values) {
      timer.cancel();
    }
    _pendingReconnectionTimers.clear();
    _disconnectedPlayers.clear();

    _connectedPlayersCtrl.value = const [];

    try {
      await _server?.close();
    } catch (e) {
      debugPrint('WsTransport server close error: $e');
    }
    _server = null;
    _serverActiveCtrl.value = false;
    _connectionStatusCtrl.value = '';

    if (_clientSocket != null) {
      try {
        _clientSocket!.close();
      } catch (e) {
        debugPrint('WsTransport client socket close error: $e');
      }
      _clientSocket = null;
    }
    _clientSub?.cancel();
    _clientSub = null;
    _clientConnectedCtrl.value = false;
  }

  @override
  void dispose() {
    stopDiscovery();
    _serverSub?.cancel();
    _clientSub?.cancel();
    for (final sub in _clientSubs) {
      sub.cancel();
    }
    for (final socket in _connections.values) {
      try {
        socket.close();
      } catch (_) {}
    }
    // Limpiar timers de reconexión pendientes
    for (final timer in _pendingReconnectionTimers.values) {
      timer.cancel();
    }
    _pendingReconnectionTimers.clear();
    _disconnectedPlayers.clear();

    try {
      _server?.close();
    } catch (_) {}
    try {
      _clientSocket?.close();
    } catch (_) {}
    _connectedPlayersCtrl.dispose();
    _clientConnectedCtrl.dispose();
    _serverActiveCtrl.dispose();
    _discoveredBanksCtrl.dispose();
    _connectionStatusCtrl.dispose();
  }

  // --- UDP Discovery ---
  // Bank: broadcasts its presence every 2s so wallets find it automatically
  // Wallet: listens passively on discoveryPort for bank announcements

  Future<void> startDiscovery({required bool isBank}) async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    try {
      if (isBank) {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
        );
        _discoverySocket!.broadcastEnabled = true;

        _discoverySub = _discoverySocket!.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = _discoverySocket?.receive();
          if (datagram == null) return;
          final msg = utf8.decode(datagram.data);
          _handleBankDiscoveryRequest(msg, datagram);
        });

        _broadcastPresence();
        _discoveryTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => _broadcastPresence(),
        );
      } else {
        // Wallet: bind to discoveryPort to receive bank broadcasts directly
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
        );
        _discoverySocket!.broadcastEnabled = true;

        _discoverySub = _discoverySocket!.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = _discoverySocket?.receive();
          if (datagram == null) return;
          final msg = utf8.decode(datagram.data);
          _handleWalletDiscoveryResponse(msg);
        });

        // Actively ask for banks + listen for broadcasts
        _sendDiscoveryBroadcast();
        // Burst of additional broadcasts to overcome socket init-timing hiccup on Windows
        for (int i = 0; i < 3; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (!_isDiscovering) break;
          _sendDiscoveryBroadcast();
        }
        _discoveryTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) {
            _sendDiscoveryBroadcast();
            _sweepStaleBanks();
          },
        );
      }
    } catch (e) {
      _isDiscovering = false;
      debugPrint('WsTransport startDiscovery error: $e');
    }
  }

  void _broadcastPresence() {
    if (_localIp == null) return;
    try {
      final data = utf8.encode('$_discoveryResponse|$_localIp|$_port');
      _discoverySocket?.send(
        data,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (e) {
      debugPrint('WsTransport broadcastPresence error: $e');
    }
  }

  void _sendDiscoveryBroadcast() {
    try {
      final data = utf8.encode(_discoveryRequest);
      _discoverySocket?.send(
        data,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (e) {
      debugPrint('WsTransport sendDiscoveryBroadcast error: $e');
    }
  }

  void _handleBankDiscoveryRequest(String msg, Datagram datagram) {
    if (msg == _discoveryRequest && _localIp != null) {
      final response = utf8.encode('$_discoveryResponse|$_localIp|$_port');
      _discoverySocket?.send(response, datagram.address, datagram.port);
    }
  }

  void _handleWalletDiscoveryResponse(String msg) {
    if (!msg.startsWith('$_discoveryResponse|')) return;
    final parts = msg.split('|');
    if (parts.length < 3) return;

    final ip = parts[1];
    final port = int.tryParse(parts[2]) ?? defaultPort;
    if (ip.isEmpty) return;

    final now = DateTime.now();
    _bankLastSeen[ip] = now;

    final list = List<DiscoveredBank>.from(_discoveredBanksCtrl.value);
    final idx = list.indexWhere((b) => b.ip == ip);
    if (idx >= 0) {
      list[idx] = DiscoveredBank(ip: ip, port: port, lastSeen: now);
    } else {
      list.add(DiscoveredBank(ip: ip, port: port, lastSeen: now));
    }
    _discoveredBanksCtrl.value = list;
  }

  void _sweepStaleBanks() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    final toRemove = <String>[];
    _bankLastSeen.forEach((ip, lastSeen) {
      if (lastSeen.isBefore(cutoff)) toRemove.add(ip);
    });
    if (toRemove.isEmpty) return;
    for (final ip in toRemove) {
      _bankLastSeen.remove(ip);
    }
    _discoveredBanksCtrl.value = _discoveredBanksCtrl.value
        .where((b) => _bankLastSeen.containsKey(b.ip))
        .toList();
  }

  void stopDiscovery() {
    _isDiscovering = false;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _discoverySub?.cancel();
    _discoverySub = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    _discoveredBanksCtrl.value = const [];
    _bankLastSeen.clear();
  }
}
