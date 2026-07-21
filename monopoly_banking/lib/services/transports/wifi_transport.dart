import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/tcp_channel.dart';

class WifiTransport extends P2PTransport {
  @override
  String get name => 'WiFi';

  @override
  IconData get icon => Icons.wifi_rounded;

  @override
  String get description => 'Conexi\u00f3n WiFi en red local';

  @override
  bool get isEnabled => true;

  static const int _discoveryPort = 43210;
  static const String _discoveryMagic = 'MONOPOLY_P2P';

  final _tcp = TcpChannel();

  RawDatagramSocket? _udpSocket;
  StreamSubscription<RawSocketEvent>? _udpSub;
  bool _isReceiving = false;

  Timer? _announceTimer;

  @override
  Future<void> initialize() async {
    await _tcp.startServer();
  }

  @override
  Future<void> startReceiving(
      void Function(Map<String, dynamic>) onData) async {
    if (_isReceiving) return;
    _isReceiving = true;

    _tcpDataSub = _tcp.onData.listen(
      onData,
      onError: (e) => debugPrint('WifiTransport tcp onData error: $e'),
    );

    try {
      _udpSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _udpSocket!.broadcastEnabled = true;

      _udpSub = _udpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _udpSocket?.receive();
        if (datagram == null) return;
        try {
          final msg = utf8.decode(datagram.data);
          if (msg.startsWith(_discoveryMagic)) {
            final parts = msg.split('|');
            if (parts.length >= 3) {
              final remoteIp = datagram.address.address;
              final remotePort = int.tryParse(parts[1]) ?? 0;
              if (remotePort > 0) {
                _tcp.sendTo(
                    remoteIp, remotePort, {'type': '_wifi_discovery_ack'});
              }
            }
          }
        } catch (e) {
          debugPrint('WifiTransport discovery parse error: $e');
        }
      });
    } catch (e) {
      debugPrint('WifiTransport UDP bind error: $e');
    }

    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isReceiving || _tcp.localIp == null) return;
      final msg = '$_discoveryMagic|${_tcp.port}|${_tcp.localIp}';
      try {
        _udpSocket?.send(
          utf8.encode(msg),
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
      } catch (e) {
        debugPrint('WifiTransport announce error: $e');
      }
    });
  }

  StreamSubscription<Map<String, dynamic>>? _tcpDataSub;

  @override
  Future<void> sendPayload(Map<String, dynamic> payload) async {
    final localIp = _tcp.localIp;
    if (localIp == null) {
      debugPrint('WifiTransport sendPayload: localIp is null');
      return;
    }

    RawDatagramSocket? udp;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udp.broadcastEnabled = true;

      final msg = '$_discoveryMagic|${_tcp.port}|$localIp';
      udp.send(
          utf8.encode(msg), InternetAddress('255.255.255.255'), _discoveryPort);

      final completer = Completer<void>();
      final timer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.complete();
      });

      sub = udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = udp?.receive();
        if (datagram == null) return;
        try {
          final response = utf8.decode(datagram.data);
          if (response == '_wifi_discovery_ack') return;
          if (response.startsWith(_discoveryMagic)) {
            final parts = response.split('|');
            if (parts.length >= 3) {
              final remoteIp = parts[2];
              final remotePort = int.tryParse(parts[1]) ?? 0;
              if (remotePort > 0 && remoteIp != localIp) {
                timer.cancel();
                if (!completer.isCompleted) completer.complete();
                _tcp.sendTo(remoteIp, remotePort, payload);
              }
            }
          }
        } catch (e) {
          debugPrint('WifiTransport sendPayload parse error: $e');
        }
      });

      await completer.future;
    } catch (e) {
      debugPrint('WifiTransport sendPayload error: $e');
    } finally {
      sub?.cancel();
      udp?.close();
    }
  }

  @override
  Future<void> stop() async {
    _isReceiving = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    _tcpDataSub?.cancel();
    _tcpDataSub = null;
    _udpSub?.cancel();
    _udpSub = null;
    try {
      _udpSocket?.close();
    } catch (_) {}
    _udpSocket = null;
    await _tcp.stop();
  }

  @override
  void dispose() {
    _announceTimer?.cancel();
    _tcpDataSub?.cancel();
    _udpSub?.cancel();
    _udpSocket?.close();
    _tcp.dispose();
  }
}
