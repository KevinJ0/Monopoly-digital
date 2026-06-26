import 'dart:async';
import 'package:flutter/material.dart';

abstract class P2PTransport {
  String get name;
  IconData get icon;
  String get description;
  bool get isEnabled;
  Future<void> initialize();
  Future<void> startReceiving(void Function(Map<String, dynamic>) onData);
  Future<void> sendPayload(Map<String, dynamic> payload);
  Future<void> stop();
  void dispose();
}

class TransportUnavailableException implements Exception {
  final String transportName;
  TransportUnavailableException(this.transportName);
  @override
  String toString() => '$transportName no est\u00e1 disponible';
}
