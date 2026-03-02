import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../models/usuario_model.dart';

enum BancoState { IDLE, WAIT_EMISOR, WAIT_RECEPTOR }

class BancoLogic {
  ServerSocket? _serverSocket;
  final List<Socket> _clientes = [];
  List<UsuarioModel> usuarios = [];

  BancoState estado = BancoState.IDLE;
  String? _emisorPendiente;
  double _montoPendiente = 0;

  final StreamController<BancoState> estadoController = StreamController<BancoState>.broadcast();
  final StreamController<List<UsuarioModel>> usuariosController = StreamController<List<UsuarioModel>>.broadcast();

  Future<void> iniciarServidor() async {
    await _cargarUsuarios();
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 8080);
    _serverSocket!.listen((Socket socket) {
      if (!_clientes.contains(socket)) {
        _clientes.add(socket);
      }
      _notificarUsuarios();

      socket.listen(
        (List<int> data) {
          final stringData = utf8.decode(data);
          final msgs = stringData.split('\n').where((s) => s.trim().isNotEmpty);
          for (var msg in msgs) {
            _procesarMensaje(socket, msg);
          }
        },
        onDone: () {
          _clientes.remove(socket);
          socket.close();
        },
        onError: (e) {
          _clientes.remove(socket);
          socket.close();
        },
      );
    });
  }

  Future<void> _cargarUsuarios() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/USUARIOS.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final List<dynamic> data = jsonDecode(jsonStr);
        usuarios = data.map((json) => UsuarioModel.fromJson(json)).toList();
      } else {
        usuarios = [];
      }
    } catch (e) {
      usuarios = [];
    }
    usuariosController.add(usuarios);
  }

  Future<void> _guardarUsuarios() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/USUARIOS.json');
    final jsonList = usuarios.map((u) => u.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
    _notificarUsuarios();
  }

  void _notificarUsuarios() {
    usuariosController.add(usuarios);
    final msg = jsonEncode({'tipo': 'usuarios', 'data': usuarios.map((u) => u.toJson()).toList()}) + '\n';
    for (var cliente in _clientes) {
      try {
        cliente.write(msg);
      } catch (e) {
        // Ignorar error al escribir
      }
    }
  }

  void _procesarMensaje(Socket socket, String mensaje) {
    try {
      final data = jsonDecode(mensaje);
      final tipo = data['tipo'];

      if (tipo == 'transferencia_directa') {
        _transferenciaDirecta(data['emisor'], data['receptor'], (data['monto'] ?? 0).toDouble());
      } else if (tipo == 'transferencia_fisica') {
        _procesarTransferenciaFisica(data['rol'], data['usuarioId'], (data['monto'] ?? 0).toDouble());
      } else if (tipo == 'consultar_usuarios') {
        _notificarUsuarios();
      }
    } catch (e) {}
  }

  void _transferenciaDirecta(String emisorId, String receptorId, double monto) async {
    try {
      var emisor = usuarios.firstWhere((u) => u.usuarioId == emisorId);
      var receptor = usuarios.firstWhere((u) => u.usuarioId == receptorId);
      if (emisor.trevnot >= monto) {
        emisor.trevnot -= monto;
        receptor.trevnot += monto;
        await _guardarUsuarios();
      }
    } catch (e) {}
  }

  void _procesarTransferenciaFisica(String rol, String usuarioId, double monto) async {
    try {
      if (rol == 'Entrega' && estado == BancoState.WAIT_EMISOR) {
        var emisor = usuarios.firstWhere((u) => u.usuarioId == usuarioId);
        if (emisor.trevnot >= monto) {
          emisor.trevnot -= monto;
          _emisorPendiente = usuarioId;
          _montoPendiente = monto;
          await _guardarUsuarios();
          _cambiarEstado(BancoState.WAIT_RECEPTOR);
        }
      } else if (rol == 'Recibe' && estado == BancoState.WAIT_RECEPTOR) {
        var receptor = usuarios.firstWhere((u) => u.usuarioId == usuarioId);
        receptor.trevnot += _montoPendiente;
        _emisorPendiente = null;
        _montoPendiente = 0;
        await _guardarUsuarios();
        _cambiarEstado(BancoState.IDLE);
      }
    } catch (e) {}
  }

  void setEstadoEsperandoEmisor() {
    _cambiarEstado(BancoState.WAIT_EMISOR);
  }

  void cancelarTransferenciaFisica() async {
    if (_emisorPendiente != null && _montoPendiente > 0) {
      try {
        var emisor = usuarios.firstWhere((u) => u.usuarioId == _emisorPendiente);
        emisor.trevnot += _montoPendiente;
        await _guardarUsuarios();
      } catch (e) {}
    }
    _emisorPendiente = null;
    _montoPendiente = 0;
    _cambiarEstado(BancoState.IDLE);
  }

  void _cambiarEstado(BancoState nuevoEstado) {
    estado = nuevoEstado;
    estadoController.add(estado);
    final msg = jsonEncode({'tipo': 'estado_banco', 'estado': estado.toString()}) + '\n';
    for (var cliente in _clientes) {
      try {
        cliente.write(msg);
      } catch (e) {}
    }
  }

  void detenerServidor() {
    for (var cliente in _clientes) {
      cliente.close();
    }
    _clientes.clear();
    _serverSocket?.close();
    _serverSocket = null;
  }
}
