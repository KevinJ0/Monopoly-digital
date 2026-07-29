import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WsDebugScreen extends StatefulWidget {
  const WsDebugScreen({super.key});

  @override
  State<WsDebugScreen> createState() => _WsDebugScreenState();
}

class _WsDebugScreenState extends State<WsDebugScreen> {
  final List<String> _logs = [];
  final _logCtrl = ScrollController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '7070');
  final _msgCtrl = TextEditingController();

  HttpServer? _server;
  WebSocket? _serverClient;
  WebSocket? _clientSocket;
  bool _serverRunning = false;
  bool _clientConnected = false;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _findIp();
  }

  @override
  void dispose() {
    _server?.close();
    _serverClient?.close();
    _clientSocket?.close();
    _logCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    setState(() => _logs.add('[$ts] $msg'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.animateTo(_logCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _findIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final octets = addr.address.split('.');
            final first = int.tryParse(octets[0]) ?? 0;
            final second = int.tryParse(octets[1]) ?? 0;
            final isTailscale = first == 100 && second >= 64 && second <= 127;
            final label = isTailscale ? ' [Tailscale]' : '';
            _log('Interface: ${iface.name} => ${addr.address}$label');
            if (isTailscale && _localIp == null) {
              setState(() => _localIp = addr.address);
            }
            _localIp ??= addr.address;
          }
        }
      }
      setState(() {});
      if (_localIp != null) _log('Using IP: $_localIp');
    } catch (e) {
      _log('Error finding IP: $e');
    }
  }

  Future<void> _startServer() async {
    final port = int.tryParse(_portCtrl.text.trim()) ?? 7070;
    try {
      _log('Starting server on 0.0.0.0:$port...');
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _serverRunning = true;
      _log('Server ACTIVE on port ${_server!.port}');

      _server!.listen((HttpRequest request) {
        final addr = request.connectionInfo?.remoteAddress.address ?? '?';
        _log('HTTP request from $addr path=${request.uri.path}');

        if (request.uri.path == '/') {
          WebSocketTransformer.upgrade(request).then((ws) {
            _log('WebSocket UPGRADED from $addr');
            _serverClient = ws;
            ws.listen(
              (data) => _log('SERVER RX: $data'),
              onDone: () {
                _log('Client DISCONNECTED from $addr');
                _serverClient = null;
              },
              onError: (e) => _log('Client ERROR: $e'),
            );
          }).catchError((e) {
            _log('WebSocket upgrade FAILED from $addr: $e');
          });
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });
    } catch (e) {
      _log('Server FAILED: $e');
      _serverRunning = false;
    }
    setState(() {});
  }

  Future<void> _stopServer() async {
    await _server?.close();
    _server = null;
    _serverClient?.close();
    _serverClient = null;
    _serverRunning = false;
    _log('Server STOPPED');
    setState(() {});
  }

  Future<void> _connectClient() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 7070;
    if (host.isEmpty) {
      _log('ERROR: Enter a host IP');
      return;
    }
    try {
      _log('Connecting to ws://$host:$port ...');
      _clientSocket = await WebSocket.connect('ws://$host:$port')
          .timeout(const Duration(seconds: 8));
      _clientConnected = true;
      _log('Client CONNECTED to $host:$port');

      _clientSocket!.listen(
        (data) => _log('CLIENT RX: $data'),
        onDone: () {
          _log('Client DISCONNECTED');
          _clientConnected = false;
          setState(() {});
        },
        onError: (e) {
          _log('Client ERROR: $e');
          _clientConnected = false;
          setState(() {});
        },
      );
    } catch (e) {
      _log('Client FAILED: $e');
      _clientConnected = false;
    }
    setState(() {});
  }

  void _disconnectClient() {
    _clientSocket?.close();
    _clientSocket = null;
    _clientConnected = false;
    _log('Client DISCONNECTED');
    setState(() {});
  }

  void _sendToServer() {
    if (_serverClient == null) {
      _log('No client connected to server');
      return;
    }
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    _serverClient!.add(msg);
    _log('SERVER TX: $msg');
    _msgCtrl.clear();
  }

  void _sendToClient() {
    if (_clientSocket == null) {
      _log('Not connected as client');
      return;
    }
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    _clientSocket!.add(msg);
    _log('CLIENT TX: $msg');
    _msgCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('WS Debug', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_localIp != null) {
                        Clipboard.setData(ClipboardData(text: _localIp!));
                        _log('IP copied: $_localIp');
                      }
                    },
                    child: Text('IP: ${_localIp ?? "loading..."} (tap to copy)',
                        style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Host IP',
                            hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF0D1117),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363D))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: 'Port',
                            hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF0D1117),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363D))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _serverRunning ? _stopServer : _startServer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _serverRunning ? const Color(0xFFDA3633) : const Color(0xFF238636),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(_serverRunning ? 'STOP SERVER' : 'START SERVER', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _clientConnected ? _disconnectClient : _connectClient,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _clientConnected ? const Color(0xFFDA3633) : const Color(0xFF1F6FEB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(_clientConnected ? 'DISCONNECT' : 'CONNECT', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF0D1117),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363D))),
                          ),
                          onSubmitted: (_) => _sendToServer(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sendToServer,
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF58A6FF), size: 20),
                        tooltip: 'Send (server)',
                      ),
                      IconButton(
                        onPressed: _sendToClient,
                        icon: const Icon(Icons.send_and_archive_rounded, color: Color(0xFF3FB950), size: 20),
                        tooltip: 'Send (client)',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('LOG', style: TextStyle(color: Color(0xFF8B949E), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: _logs.isEmpty
                    ? const Center(child: Text('No logs yet', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)))
                    : ListView.builder(
                        controller: _logCtrl,
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final log = _logs[i];
                          final color = log.contains('FAILED') || log.contains('ERROR')
                              ? const Color(0xFFF85149)
                              : log.contains('CONNECTED') || log.contains('ACTIVE') || log.contains('OK')
                                  ? const Color(0xFF3FB950)
                                  : log.contains('TX:')
                                      ? const Color(0xFF58A6FF)
                                      : log.contains('RX:')
                                          ? const Color(0xFFD2A8FF)
                                          : const Color(0xFF8B949E);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(log, style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace')),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
