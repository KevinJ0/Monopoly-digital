import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum TransferState { idle, listening, waitingSender, holding, waitingReceiver }

class BancoServer {
  static final BancoServer _instance = BancoServer._();
  factory BancoServer() => _instance;
  BancoServer._();

  ServerSocket? _server;
  final List<Socket> _clients = [];
  final Map<Socket, Map<String, dynamic>> _clientUsers = {};
  final Map<Socket, List<int>> _clientBuffers = {};
  Map<String, dynamic> _db = {};
  TransferState state = TransferState.idle;

  Map<String, dynamic>? _transactionTemp;
  final _stateController = StreamController<TransferState>.broadcast();
  Stream<TransferState> get stateStream => _stateController.stream;

  final _clientsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get connectedPlayers =>
      _clientsController.stream;

  Future<void> start() async {
    try {
      await _loadDatabase();
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 8080);
      _server!.listen(_handleConnection);
      _updateState(TransferState.listening);
    } catch (e) {
      _stateController.addError('Error al iniciar servidor: $e');
    }
  }

  Future<void> _loadDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/USUARIOS.json');
    if (await file.exists()) {
      _db = jsonDecode(await file.readAsString());
    } else {
      _db = {"users": []};
      await file.writeAsString(jsonEncode(_db));
    }
  }

  Future<void> _saveDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/USUARIOS.json');
    await file.writeAsString(jsonEncode(_db));
  }

  void _handleConnection(Socket client) {
    _clients.add(client);
    _clientBuffers[client] = [];
    client.listen(
      (data) => _handleSyncMessage(client, data),
      onDone: () {
        _clients.remove(client);
        _clientUsers.remove(client);
        _clientBuffers.remove(client);
        _broadcastConnectedPlayers();
        _broadcastPlayers();
      },
      onError: (e) {
        debugPrint('BancoServer client error: $e');
        _clients.remove(client);
        _clientUsers.remove(client);
        _clientBuffers.remove(client);
        _broadcastConnectedPlayers();
        _broadcastPlayers();
      },
    );
  }

  void _handleSyncMessage(Socket client, List<int> data) {
    final buffer = _clientBuffers[client];
    if (buffer == null) return;

    buffer.addAll(data);

    while (buffer.length >= 4) {
      final length = (buffer[0] << 24) |
          (buffer[1] << 16) |
          (buffer[2] << 8) |
          buffer[3];

      if (buffer.length < 4 + length) break;

      final messageBytes = buffer.sublist(4, 4 + length);
      buffer.removeRange(0, 4 + length);

      try {
        final msg = jsonDecode(utf8.decode(messageBytes));
        if (msg is Map<String, dynamic>) {
          _processMessage(client, msg);
        }
      } catch (e) {
        debugPrint('BancoServer json decode error: $e');
      }
    }
  }

  void _processMessage(Socket client, Map<String, dynamic> msg) {
    final type = msg['type'];

    if (type == 'register') {
      final user = msg['user'];
      if (user is Map<String, dynamic>) {
        _updateUserInDb(user);
        _clientUsers[client] = Map<String, dynamic>.from(user);
        _broadcastConnectedPlayers();
        _broadcastPlayers();
      }
    } else if (type == 'request_transfer') {
      final from = msg['from'] as String?;
      final to = msg['to'] as String?;
      final amount = (msg['amount'] as num?)?.toDouble();
      if (from != null && to != null && amount != null) {
        _initiateManualTransfer(from, to, amount);
      }
    } else if (type == 'confirm_phase') {
      final userId = msg['userId'] as String?;
      if (userId != null) {
        _processConfirmation(userId);
      }
    }
  }

  void _updateUserInDb(Map<String, dynamic> user) {
    final users = _db['users'];
    if (users is! List) return;
    final userId = user['USUARIOID'];
    int idx = users.indexWhere((u) => u['USUARIOID'] == userId);
    if (idx != -1) {
      users[idx] = user;
    } else {
      users.add(user);
    }
    _saveDatabase();
  }

  void _broadcastConnectedPlayers() {
    final activePlayers = _clientUsers.entries.map((entry) {
      final user = Map<String, dynamic>.from(entry.value);
      user['transport'] = 'WiFi';
      user['quality'] = 'Buena';
      user['qualityColor'] = 'green';
      user['address'] = entry.key.remoteAddress.address;
      return user;
    }).toList(growable: false);
    _clientsController.add(activePlayers);
  }

  void _broadcastPlayers() {
    final players = _db['users'];
    if (players is! List) return;
    final msgBytes = _encodeWithLength({'type': 'player_list', 'players': players});
    for (var c in _clients) {
      try {
        c.add(msgBytes);
      } catch (e) {
        debugPrint('BancoServer broadcast write error: $e');
      }
    }
  }

  void _initiateManualTransfer(String fromId, String toId, double amount) {
    if (state != TransferState.listening && state != TransferState.idle) return;

    final users = _db['users'];
    if (users is! List) return;
    final senderIdx = users.indexWhere((u) => u['USUARIOID'] == fromId);
    if (senderIdx == -1) {
      _sendToAll({'type': 'error', 'msg': 'Remitente no encontrado'});
      return;
    }
    final sender = users[senderIdx];

    if ((sender['TREVNOT'] ?? 0) < amount) {
      _sendToAll({'type': 'error', 'msg': 'Saldo insuficiente'});
      return;
    }

    _transactionTemp = {'from': fromId, 'to': toId, 'amount': amount};
    _updateState(TransferState.waitingSender);
  }

  void _processConfirmation(String userId) {
    if (state == TransferState.waitingSender &&
        userId == _transactionTemp?['from']) {
      _debitSender();
    } else if (state == TransferState.waitingReceiver &&
        userId == _transactionTemp?['to']) {
      _creditReceiver();
    }
  }

  void _debitSender() {
    final users = _db['users'];
    if (users is! List) return;
    int idx =
        users.indexWhere((u) => u['USUARIOID'] == _transactionTemp?['from']);
    if (idx == -1) return;
    users[idx]['TREVNOT'] -= _transactionTemp?['amount'];
    _saveDatabase();
    _broadcastPlayers();
    _updateState(TransferState.holding);

    Future.delayed(const Duration(seconds: 1), () {
      _updateState(TransferState.waitingReceiver);
    });
  }

  void _creditReceiver() {
    final users = _db['users'];
    if (users is! List) return;
    int idx =
        users.indexWhere((u) => u['USUARIOID'] == _transactionTemp?['to']);
    if (idx == -1) return;
    users[idx]['TREVNOT'] += _transactionTemp?['amount'];
    _saveDatabase();
    _broadcastPlayers();
    _updateState(TransferState.listening);
    _transactionTemp = null;
  }

  void _updateState(TransferState s) {
    state = s;
    _stateController.add(s);
    _sendToAll({'type': 'transfer_state', 'state': s.name});
  }

  void _sendToAll(Map<String, dynamic> msg) {
    final data = _encodeWithLength(msg);
    for (var c in _clients) {
      try {
        c.add(data);
      } catch (e) {
        debugPrint('BancoServer _sendToAll write error: $e');
      }
    }
  }

  static List<int> _encodeWithLength(Map<String, dynamic> msg) {
    final jsonBytes = utf8.encode(jsonEncode(msg));
    return [
      (jsonBytes.length >> 24) & 0xFF,
      (jsonBytes.length >> 16) & 0xFF,
      (jsonBytes.length >> 8) & 0xFF,
      jsonBytes.length & 0xFF,
      ...jsonBytes,
    ];
  }
}

class JugadorClient {
  static final JugadorClient _instance = JugadorClient._();
  factory JugadorClient() => _instance;
  JugadorClient._();

  Socket? _socket;
  final List<int> _buffer = [];
  final _playersController = StreamController<List<dynamic>>.broadcast();
  Stream<List<dynamic>> get playersStream => _playersController.stream;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  Future<void> connect(Map<String, dynamic> userData) async {
    final potentialGws = <String>{'192.168.43.1', '172.20.10.1', '10.0.0.1'};

    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              potentialGws.add('${parts[0]}.${parts[1]}.${parts[2]}.1');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('JugadorClient network scan error: $e');
    }

    // Limitar a máximo 5 intentos para evitar timeouts largos
    final ips = potentialGws.take(5).toList();
    String lastError = 'No se encontró el servidor del Banco';

    for (final ip in ips) {
      try {
        _socket =
            await Socket.connect(ip, 8080, timeout: const Duration(seconds: 1));
        final registerMsg = _encodeWithLength({'type': 'register', 'user': userData});
        _socket!.add(registerMsg);
        await _socket!.flush();
        _socket!.listen(_handleMessage,
            onDone: () {
              _socket = null;
              _buffer.clear();
            },
            onError: (e) {
              debugPrint('JugadorClient socket error: $e');
              _socket = null;
              _buffer.clear();
            });
        return;
      } catch (e) {
        lastError = e.toString();
      }
    }
    throw Exception(
        'Error de conexión: $lastError. Verifica que el Banco tenga el Punto de Acceso activo.');
  }

  void _handleMessage(List<int> data) {
    _buffer.addAll(data);

    while (_buffer.length >= 4) {
      final length = (_buffer[0] << 24) |
          (_buffer[1] << 16) |
          (_buffer[2] << 8) |
          _buffer[3];

      if (_buffer.length < 4 + length) break;

      final messageBytes = _buffer.sublist(4, 4 + length);
      _buffer.removeRange(0, 4 + length);

      try {
        final msg = jsonDecode(utf8.decode(messageBytes));
        if (msg is Map<String, dynamic>) {
          if (msg['type'] == 'player_list') {
            _playersController.add(msg['players']);
          } else {
            _messageController.add(msg);
          }
        }
      } catch (e) {
        debugPrint('JugadorClient json decode error: $e');
      }
    }
  }

  void requestTransfer(String toId, double amount, String myId) {
    if (_socket == null) {
      debugPrint('JugadorClient: no socket connected');
      return;
    }
    final data = _encodeWithLength({
      'type': 'request_transfer',
      'from': myId,
      'to': toId,
      'amount': amount,
    });
    _socket!.add(data);
  }

  void confirmAction(String myId) {
    if (_socket == null) {
      debugPrint('JugadorClient: no socket connected');
      return;
    }
    final data = _encodeWithLength({
      'type': 'confirm_phase',
      'userId': myId,
    });
    _socket!.add(data);
  }

  static List<int> _encodeWithLength(Map<String, dynamic> msg) {
    final jsonBytes = utf8.encode(jsonEncode(msg));
    return [
      (jsonBytes.length >> 24) & 0xFF,
      (jsonBytes.length >> 16) & 0xFF,
      (jsonBytes.length >> 8) & 0xFF,
      jsonBytes.length & 0xFF,
      ...jsonBytes,
    ];
  }
}
