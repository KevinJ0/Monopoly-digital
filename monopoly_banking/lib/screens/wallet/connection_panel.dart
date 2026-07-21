part of '../wallet_screen.dart';

class ConnectionPanel extends StatelessWidget {
  final Color color;
  final bool isBank;
  final bool wsScanning;
  final VoidCallback? onStopWsClient;
  final VoidCallback? onStartWsClient;
  final void Function(String host, int port)? onConnectToWsBank;

  const ConnectionPanel({
    super.key,
    required this.color,
    required this.isBank,
    required this.wsScanning,
    this.onStopWsClient,
    this.onStartWsClient,
    this.onConnectToWsBank,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransportType>(
      valueListenable: P2PService().typeNotifier,
      builder: (context, currentTransport, _) {
        if (isBank) {
          return const SizedBox.shrink();
        }
        return WsConnectButton(
          key: const ValueKey('wsConnect'),
          color: color,
          scanning: wsScanning,
          clientConnected: P2PService().wsTransport.clientConnectedNotifier.value,
          connecting: false,
          onStartWsClient: onStartWsClient,
          onStopWsClient: onStopWsClient,
          onConnectToBank: onConnectToWsBank,
        );
      },
    );
  }
}

class ConnectedPlayersPanel extends StatelessWidget {
  final Color color;
  final void Function(WsPlayer player)? onPlayerTap;

  const ConnectedPlayersPanel({
    super.key,
    required this.color,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    final transport = P2PService().wsTransport;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ValueListenableBuilder<List<WsPlayer>>(
        valueListenable: transport.connectedPlayersNotifier,
        builder: (context, wsPlayers, _) {
          final total = wsPlayers.where((p) => p.connected).length;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kBgCard.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_rounded, color: color, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Jugadores conectados',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '$total',
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (total == 0) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Sin jugadores activos',
                    style: TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  ...wsPlayers.where((p) => p.connected).map((player) {
                    final detail =
                        '${player.connected ? 'Conectado' : 'Desconectado'}';
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onPlayerTap?.call(player),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: kBgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ConnectedPlayerTile(
                                name: player.displayName,
                                deviceName: '',
                                transport: 'WS',
                                detail: detail,
                                color: player.connected ? kGreen : Colors.grey,
                                icon: Icons.wifi_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
