import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  final _connectedPlayersCtrl =
      ValueNotifier<List<WsPlayer>>(const []);
  ValueNotifier<List<WsPlayer>> get connectedPlayersNotifier =>
      _connectedPlayersCtrl;

  final _clientConnectedCtrl = ValueNotifier<bool>(false);
  ValueNotifier<bool> get clientConnectedNotifier => _clientConnectedCtrl;

  final _serverActiveCtrl = ValueNotifier<bool>(false);
  ValueNotifier<bool> get serverActiveNotifier => _serverActiveCtrl;

  String? _localIp;
  int _port = 0;

  String? get localIp => _localIp;
  int get port => _port;

  void Function(Map<String, dynamic>)? _onData;
  StreamSubscription<dynamic>? _serverSub;
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
    } catch (_) {}
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

      _serverSub = _server!.listen((HttpRequest request) {
        if (request.uri.path == '/') {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _handleClientConnection(socket);
          }).catchError((_) {});
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });
    } catch (e) {
      _isReceiving = false;
      _serverActiveCtrl.value = false;
      rethrow;
    }
  }

  void _handleClientConnection(WebSocket socket) {
    final playerId = 'ws-${DateTime.now().microsecondsSinceEpoch}';
    socket.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          decoded['_wsPlayerId'] = playerId;

          if (decoded['type'] == 'ws_identity') {
            final name = decoded['name'] as String? ?? '';
            final avatarId = decoded['avatarId'] as String? ?? '';
            final colorId = decoded['colorId'] as String? ?? '0';
            final installationId =
                decoded['deviceInstallationId'] as String? ?? '';

            _connections[playerId] = socket;
            if (installationId.isNotEmpty) {
              _connectionsByInstallationId[installationId] = playerId;
            }

            final existing = _connectedPlayersCtrl.value.indexWhere(
                (p) => p.id == playerId);
            final player = WsPlayer(
              id: playerId,
              name: name,
              avatarId: avatarId,
              colorId: colorId,
              deviceInstallationId: installationId,
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
            return;
          }

          _onData?.call(decoded);
        } catch (_) {}
      },
      onDone: () {
        _removeClient(playerId);
      },
      onError: (_) {
        _removeClient(playerId);
      },
    );
    _clientSubs.add(socket as StreamSubscription<dynamic>);
  }

  void _removeClient(String playerId) {
    _connections.remove(playerId);
    _connectionsByInstallationId.removeWhere((_, id) => id == playerId);

    final list = List<WsPlayer>.from(_connectedPlayersCtrl.value);
    list.removeWhere((p) => p.id == playerId);
    _connectedPlayersCtrl.value = list;
  }

  Future<void> connectToBank(String host, {int port = defaultPort}) async {
    try {
      _clientSocket = await WebSocket.connect('ws://$host:$port');
      _clientConnectedCtrl.value = true;

      _clientSocket!.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _onData?.call(decoded);
          } catch (_) {}
        },
        onDone: () {
          _clientConnectedCtrl.value = false;
          _clientSocket = null;
        },
        onError: (_) {
          _clientConnectedCtrl.value = false;
          _clientSocket = null;
        },
      );
    } catch (e) {
      _clientConnectedCtrl.value = false;
      rethrow;
    }
  }

  void sendIdentity({
    required String name,
    required String avatarId,
    required String colorId,
    required String deviceInstallationId,
  }) {
    if (_clientSocket != null && _clientSocket!.ready == WebSocket.open) {
      _clientSocket!.add(jsonEncode({
        'type': 'ws_identity',
        'name': name,
        'avatarId': avatarId,
        'colorId': colorId,
        'deviceInstallationId': deviceInstallationId,
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
    final targetPlayerId = payload['targetPlayerId'] as String?;

    if (targetPlayerId != null && targetPlayerId.isNotEmpty) {
      final player = _connectedPlayersCtrl.value.where(
        (p) => p.name == targetPlayerId,
      ).firstOrNull;
      if (player != null) {
        final socket = _connections[player.id];
        if (socket != null && socket.ready == WebSocket.open) {
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
      if (socket.ready == WebSocket.open) {
        socket.add(msg);
      }
    }
  }

  Future<void> _sendAsClient(Map<String, dynamic> payload) async {
    if (_clientSocket == null || _clientSocket!.ready != WebSocket.open) {
      throw TransportUnavailableException(
        'No hay conexi\u00f3n con el banco',
      );
    }
    _clientSocket!.add(jsonEncode(payload));
  }

  @override
  Future<void> stop() async {
    _isReceiving = false;
    _serverSub?.cancel();
    _serverSub = null;

    for (final sub in _clientSubs) {
      sub.cancel();
    }
    _clientSubs.clear();

    for (final socket in _connections.values) {
      try {
        socket.close();
      } catch (_) {}
    }
    _connections.clear();
    _connectionsByInstallationId.clear();
    _connectedPlayersCtrl.value = const [];

    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _serverActiveCtrl.value = false;

    if (_clientSocket != null) {
      try {
        _clientSocket!.close();
      } catch (_) {}
      _clientSocket = null;
    }
    _clientConnectedCtrl.value = false;
  }

  @override
  void dispose() {
    _serverSub?.cancel();
    for (final sub in _clientSubs) {
      sub.cancel();
    }
    for (final socket in _connections.values) {
      try {
        socket.close();
      } catch (_) {}
    }
    try {
      _server?.close();
    } catch (_) {}
    try {
      _clientSocket?.close();
    } catch (_) {}
    _connectedPlayersCtrl.dispose();
    _clientConnectedCtrl.dispose();
    _serverActiveCtrl.dispose();
  }
}
