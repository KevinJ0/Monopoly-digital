import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/transports/ws_models.dart';
import 'package:monopoly_banking/screens/wallet/ws_connect_button.dart';
import 'package:monopoly_banking/screens/wallet/connected_player_tile.dart';

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
          clientConnected: currentTransport == TransportType.ws,
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
    final connectedPlayers = P2PService().wsTransport.connectedPlayersNotifier;

    return ValueListenableBuilder<List<WsPlayer>>(
      valueListenable: connectedPlayers,
      builder: (context, players, _) {
        final connected = players.where((p) => p.connected).toList();
        if (connected.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.people_rounded, color: kGreen, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'JUGADORES CONECTADOS (${connected.length})',
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ...connected.map((player) => ConnectedPlayerTile(
                      displayName: player.displayName,
                      avatar: player.avatarId,
                      role: 'WS',
                      roleColor: color,
                      onTap: onPlayerTap != null ? () => onPlayerTap!(player) : null,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}
