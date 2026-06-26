import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TcpChannel {
  ServerSocket? _server;
  final _onDataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onData => _onDataController.stream;

  int _port = 0;
  String? _localIp;

  int get port => _port;
  String? get localIp => _localIp;

  Future<void> startServer({int preferredPort = 0}) async {
    await stop();
    _localIp = await _findLocalIp();
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, preferredPort);
      _port = _server!.port;
      _server!.listen((Socket client) {
        client.listen((List<int> data) {
          try {
            final msg = jsonDecode(utf8.decode(data));
            if (msg is Map<String, dynamic>) {
              _onDataController.add(msg);
            }
          } catch (_) {}
        }, onDone: () => client.close(), onError: (_) => client.close());
      });
    } catch (e) {
      _port = 0;
      rethrow;
    }
  }

  Future<String?> _findLocalIp() async {
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

  Future<void> sendTo(
      String host, int port, Map<String, dynamic> payload) async {
    Socket? socket;
    try {
      socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.add(utf8.encode(jsonEncode(payload)));
      await socket.flush();
    } finally {
      await socket?.close();
    }
  }

  Future<void> stop() async {
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _port = 0;
  }

  void dispose() {
    _onDataController.close();
  }
}
