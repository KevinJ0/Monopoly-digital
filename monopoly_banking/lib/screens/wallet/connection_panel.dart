part of '../wallet_screen.dart';

class ConnectionPanel extends StatelessWidget {
  final Color color;
  final bool isBank;
  final bool bleScanning;
  final VoidCallback? onStopBleClient;
  final VoidCallback? onStartBleClient;
  final void Function(BleBankDevice bank)? onConnectToBleBank;

  const ConnectionPanel({
    super.key,
    required this.color,
    required this.isBank,
    required this.bleScanning,
    this.onStopBleClient,
    this.onStartBleClient,
    this.onConnectToBleBank,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransportType>(
      valueListenable: P2PService().typeNotifier,
      builder: (context, currentTransport, _) {
        if (isBank) {
          return const SizedBox.shrink();
        }
        return BleClientPanel(
          color: color,
          bleScanning: bleScanning,
          onStopBleClient: onStopBleClient,
          onStartBleClient: onStartBleClient,
          onConnectToBleBank: onConnectToBleBank,
        );
      },
    );
  }
}

class ConnectedPlayersPanel extends StatelessWidget {
  final Color color;
  final void Function(BleConnectedPlayer player)? onPlayerTap;

  const ConnectedPlayersPanel({
    super.key,
    required this.color,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    final transport = P2PService().bleTransport;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ValueListenableBuilder<List<BleConnectedPlayer>>(
        valueListenable: transport.connectedPlayersNotifier,
        builder: (context, blePlayers, _) {
          final total = blePlayers.length;

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
                  ...blePlayers.map((player) {
                    final quality = player.rssi == null
                        ? player.qualityLabel
                        : '${player.qualityLabel} - ${player.rssi} dBm';
                    final detail =
                        '${player.playing ? 'Jugando' : 'Esperando handshake'} - $quality';
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onPlayerTap?.call(player),
                      child: _ConnectedPlayerTile(
                        name: player.displayName,
                        deviceName: player.displayDeviceName,
                        transport: 'BLE',
                        detail: detail,
                        color: player.playing
                            ? player.qualityColor
                            : Colors.blue,
                        icon: Icons.bluetooth_connected_rounded,
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
