

class WsPlayer {
  final String id;
  final String name;
  final String avatarId;
  final String colorId;
  final String deviceInstallationId;
  final String address;
  final bool connected;
  final bool playing;
  final DateTime lastSeen;

  WsPlayer({
    required this.id,
    this.name = '',
    this.avatarId = '',
    this.colorId = '0',
    this.deviceInstallationId = '',
    this.address = '',
    this.connected = true,
    this.playing = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  WsPlayer copyWith({
    String? id,
    String? name,
    String? avatarId,
    String? colorId,
    String? deviceInstallationId,
    String? address,
    bool? connected,
    bool? playing,
    DateTime? lastSeen,
  }) {
    return WsPlayer(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarId: avatarId ?? this.avatarId,
      colorId: colorId ?? this.colorId,
      deviceInstallationId: deviceInstallationId ?? this.deviceInstallationId,
      address: address ?? this.address,
      connected: connected ?? this.connected,
      playing: playing ?? this.playing,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  String get displayName => name.isNotEmpty ? name : 'Jugador';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WsPlayer &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DiscoveredBank {
  final String ip;
  final int port;
  final DateTime lastSeen;

  DiscoveredBank({
    required this.ip,
    required this.port,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredBank && ip == other.ip && port == other.port;

  @override
  int get hashCode => Object.hash(ip, port);
}
