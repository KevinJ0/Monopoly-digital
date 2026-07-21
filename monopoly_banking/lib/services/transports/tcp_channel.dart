import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class TcpChannel {
  ServerSocket? _server;
  final _onDataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onData => _onDataController.stream;

  int _port = 0;
  String? _localIp;
  final Map<Socket, _ClientBuffer> _clientBuffers = {};

  int get port => _port;
  String? get localIp => _localIp;

  Future<void> startServer({int preferredPort = 0}) async {
    await stop();
    _localIp = await _findLocalIp();
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, preferredPort);
      _port = _server!.port;
      _server!.listen((Socket client) {
        _clientBuffers[client] = _ClientBuffer();
        client.listen(
          (List<int> data) => _handleData(client, data),
          onDone: () {
            _clientBuffers.remove(client);
            client.close();
          },
          onError: (e) {
            debugPrint('TcpChannel client error: $e');
            _clientBuffers.remove(client);
            client.close();
          },
        );
      });
    } catch (e) {
      _port = 0;
      rethrow;
    }
  }

  void _handleData(Socket client, List<int> data) {
    final buffer = _clientBuffers[client];
    if (buffer == null) return;

    buffer.add(data);

    while (true) {
      if (!buffer.hasCompleteMessage) break;

      final jsonBytes = buffer.extractMessage();
      if (jsonBytes == null) break;

      try {
        final decoded = jsonDecode(utf8.decode(jsonBytes));
        if (decoded is Map<String, dynamic>) {
          _onDataController.add(decoded);
        }
      } catch (e) {
        debugPrint('TcpChannel json decode error: $e');
      }
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
    } catch (e) {
      debugPrint('TcpChannel findLocalIp error: $e');
    }
    return null;
  }

  Future<void> sendTo(
      String host, int port, Map<String, dynamic> payload) async {
    Socket? socket;
    try {
      socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      final jsonStr = jsonEncode(payload);
      final jsonBytes = utf8.encode(jsonStr);
      final lengthBytes = _encodeLength(jsonBytes.length);
      socket.add(lengthBytes);
      socket.add(jsonBytes);
      await socket.flush();
    } catch (e) {
      debugPrint('TcpChannel sendTo error: $e');
    } finally {
      await socket?.close();
    }
  }

  Future<void> stop() async {
    try {
      await _server?.close();
    } catch (e) {
      debugPrint('TcpChannel stop error: $e');
    }
    _clientBuffers.clear();
    _server = null;
    _port = 0;
  }

  void dispose() {
    _clientBuffers.clear();
    _onDataController.close();
  }

  static List<int> _encodeLength(int length) {
    return [
      (length >> 24) & 0xFF,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
    ];
  }
}

class _ClientBuffer {
  final BytesBuilder _builder = BytesBuilder();
  bool _hasLength = false;
  int _expectedLength = 0;

  bool get hasCompleteMessage {
    if (!_hasLength) {
      if (_builder.length < 4) return false;
      final bytes = _builder.toBytes();
      _expectedLength = (bytes[0] << 24) |
          (bytes[1] << 16) |
          (bytes[2] << 8) |
          bytes[3];
      _hasLength = true;
    }
    return _builder.length >= 4 + _expectedLength;
  }

  List<int>? extractMessage() {
    if (!hasCompleteMessage) return null;
    final all = _builder.toBytes();
    final message = all.sublist(4, 4 + _expectedLength);
    _builder.clear();
    _builder.add(all.sublist(4 + _expectedLength));
    _hasLength = false;
    _expectedLength = 0;
    return message;
  }

  void add(List<int> data) {
    _builder.add(data);
  }
}
