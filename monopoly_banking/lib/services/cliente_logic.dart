import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/usuario_model.dart';
import 'banco_logic.dart'; // Para importar BancoState si es necesario, aunque lo manejaremos como String por simplicidad

class ClienteLogic with WidgetsBindingObserver {
  Socket? _socket;
  final String usuarioId;
  final String ipBanco;

  bool _isConnecting = false;
  Timer? _reconnectTimer;

  final StreamController<List<UsuarioModel>> usuariosController =
      StreamController<List<UsuarioModel>>.broadcast();
  final StreamController<String> estadoBancoController =
      StreamController<String>.broadcast();
  final StreamController<bool> conexionController =
      StreamController<bool>.broadcast();

  ClienteLogic({required this.usuarioId, this.ipBanco = '192.168.43.1'}) {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> conectar() async {
    if (_isConnecting || _socket != null) return;
    _isConnecting = true;

    try {
      _socket = await Socket.connect(ipBanco, 8080,
          timeout: const Duration(seconds: 5));
      _isConnecting = false;
      conexionController.add(true);

      _solicitarUsuarios();

      _socket!.listen(
        (List<int> data) {
          final stringData = utf8.decode(data);
          final msgs = stringData.split('\n').where((s) => s.trim().isNotEmpty);
          for (var msg in msgs) {
            _procesarMensaje(msg);
          }
        },
        onDone: () {
          _desconexioInesperada();
        },
        onError: (e) {
          _desconexioInesperada();
        },
      );
    } catch (e) {
      _isConnecting = false;
      _desconexioInesperada();
    }
  }

  void _solicitarUsuarios() {
    _enviarMensaje({'tipo': 'consultar_usuarios'});
  }

  void _enviarMensaje(Map<String, dynamic> data) {
    if (_socket != null) {
      try {
        _socket!.write(jsonEncode(data) + '\n');
      } catch (e) {
        _desconexioInesperada();
      }
    }
  }

  void _procesarMensaje(String mensaje) {
    try {
      final jsonMsg = jsonDecode(mensaje);
      if (jsonMsg['tipo'] == 'usuarios') {
        List<dynamic> data = jsonMsg['data'];
        usuariosController
            .add(data.map((j) => UsuarioModel.fromJson(j)).toList());
      } else if (jsonMsg['tipo'] == 'estado_banco') {
        estadoBancoController.add(jsonMsg['estado']);
      }
    } catch (e) {}
  }

  void transferenciaDirecta(String receptorId, double monto) {
    _enviarMensaje({
      'tipo': 'transferencia_directa',
      'emisor': usuarioId,
      'receptor': receptorId,
      'monto': monto,
    });
  }

  void transferenciaFisica(String rol, double monto) {
    _enviarMensaje({
      'tipo': 'transferencia_fisica',
      'rol': rol,
      'usuarioId': usuarioId,
      'monto': monto,
    });
  }

  void _desconexioInesperada() {
    _socket?.destroy();
    _socket = null;
    _isConnecting = false;
    conexionController.add(false);
    _programarReconexion();
  }

  void _programarReconexion() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_socket == null) {
        conectar();
      }
    });
  }

  void desconectar() {
    _reconnectTimer?.cancel();
    _socket?.destroy();
    _socket = null;
    conexionController.add(false);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    desconectar();
    usuariosController.close();
    estadoBancoController.close();
    conexionController.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_socket == null) {
        conectar();
      }
    } else if (state == AppLifecycleState.paused) {
      // Opcional: desconectar o enviar un ping
    }
  }
}
