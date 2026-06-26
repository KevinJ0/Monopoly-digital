import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

enum TransferState { idle, listening, waitingSender, holding, waitingReceiver }

class BancoServer {
  static final BancoServer _instance = BancoServer._();
  factory BancoServer() => _instance;
  BancoServer._();

  ServerSocket? _server;
  final List<Socket> _clients = [];
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
    client.listen(
      (data) => _handleSyncMessage(client, data),
      onDone: () {
        _clients.remove(client);
        _broadcastPlayers();
      },
    );
  }

  void _handleSyncMessage(Socket client, List<int> data) {
    final msg = jsonDecode(utf8.decode(data));
    final type = msg['type'];

    if (type == 'register') {
      _updateUserInDb(msg['user']);
      _broadcastPlayers();
    } else if (type == 'request_transfer') {
      _initiateManualTransfer(msg['from'], msg['to'], msg['amount']);
    } else if (type == 'confirm_phase') {
      _processConfirmation(msg['userId']);
    }
  }

  void _updateUserInDb(Map<String, dynamic> user) {
    List users = _db['users'];
    int idx = users.indexWhere((u) => u['USUARIOID'] == user['USUARIOID']);
    if (idx != -1) {
      users[idx] = user;
    } else {
      users.add(user);
    }
    _saveDatabase();
  }

  void _broadcastPlayers() {
    final players = _db['users'];
    final data = jsonEncode({'type': 'player_list', 'players': players});
    for (var c in _clients) {
      c.write(data);
    }
    _clientsController.add(List<Map<String, dynamic>>.from(players));
  }

  void _initiateManualTransfer(String fromId, String toId, double amount) {
    if (state != TransferState.listening && state != TransferState.idle) return;

    List users = _db['users'];
    final sender = users.firstWhere((u) => u['USUARIOID'] == fromId);

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
    List users = _db['users'];
    int idx =
        users.indexWhere((u) => u['USUARIOID'] == _transactionTemp?['from']);
    users[idx]['TREVNOT'] -= _transactionTemp?['amount'];
    _saveDatabase();
    _broadcastPlayers();
    _updateState(TransferState.holding);

    Future.delayed(const Duration(seconds: 1), () {
      _updateState(TransferState.waitingReceiver);
    });
  }

  void _creditReceiver() {
    List users = _db['users'];
    int idx =
        users.indexWhere((u) => u['USUARIOID'] == _transactionTemp?['to']);
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
    final data = jsonEncode(msg);
    for (var c in _clients) {
      c.write(data);
    }
  }
}

class JugadorClient {
  static final JugadorClient _instance = JugadorClient._();
  factory JugadorClient() => _instance;
  JugadorClient._();

  Socket? _socket;
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
    } catch (_) {}

    // Limitar a máximo 5 intentos para evitar timeouts largos
    final ips = potentialGws.take(5).toList();
    String lastError = 'No se encontró el servidor del Banco';

    for (final ip in ips) {
      try {
        _socket =
            await Socket.connect(ip, 8080, timeout: const Duration(seconds: 1));
        _socket!.write(jsonEncode({'type': 'register', 'user': userData}));
        _socket!.listen(_handleMessage,
            onDone: () => _socket = null, onError: (_) => _socket = null);
        return;
      } catch (e) {
        lastError = e.toString();
      }
    }
    throw Exception(
        'Error de conexión: $lastError. Verifica que el Banco tenga el Punto de Acceso activo.');
  }

  void _handleMessage(List<int> data) {
    final msg = jsonDecode(utf8.decode(data));
    if (msg['type'] == 'player_list') {
      _playersController.add(msg['players']);
    } else {
      _messageController.add(msg);
    }
  }

  void requestTransfer(String toId, double amount, String myId) {
    _socket?.write(jsonEncode({
      'type': 'request_transfer',
      'from': myId,
      'to': toId,
      'amount': amount,
    }));
  }

  void confirmAction(String myId) {
    _socket?.write(jsonEncode({
      'type': 'confirm_phase',
      'userId': myId,
    }));
  }
}
