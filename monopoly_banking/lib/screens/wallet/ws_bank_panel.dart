import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/core/game_transitions.dart';

class WsBankPanel extends StatefulWidget {
  final VoidCallback? onReiniciarWs;
  final VoidCallback? onStopWs;
  final Future<bool> Function()? onEnsureWsReady;

  const WsBankPanel({
    super.key,
    this.onReiniciarWs,
    this.onStopWs,
    this.onEnsureWsReady,
  });

  @override
  State<WsBankPanel> createState() => _WsBankPanelState();
}

class _WsBankPanelState extends State<WsBankPanel> {
  @override
  Widget build(BuildContext context) {
    final transport = P2PService().wsTransport;

    final panel = Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: transport.serverActiveNotifier,
        builder: (context, active, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: transport.clientConnectedNotifier,
            builder: (context, connected, _) {
              return ValueListenableBuilder<String>(
                valueListenable: transport.connectionStatusNotifier,
                builder: (context, status, _) {
                  final accent = connected ? kGreen : Colors.blue;
                  final title = connected
                      ? 'JUGADOR CONECTADO'
                      : active
                          ? 'SERVIDOR WS ACTIVO'
                          : 'SERVIDOR WS';
                  final subtitle = (active && status.isNotEmpty)
                      ? status
                      : active
                          ? 'Esperando que un jugador se conecte...'
                          : 'Activa el servidor para recibir jugadores por WiFi';

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: active ? accent.withValues(alpha: 0.08) : kBgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: active ? accent.withValues(alpha: 0.45) : kBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connected ? Icons.wifi_rounded : Icons.wifi_find_rounded,
                              color: active ? accent : kTextSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: active ? accent : kTextSecondary,
                                      fontSize: 11,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active ? accent : kBorder,
                                boxShadow: active ? [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 2)] : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: active
                              ? Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              SoundService.playClick();
                                              final confirm = await _confirm(
                                                context: context,
                                                title: 'Detener servidor',
                                                message:
                                                    '\u00bfEst\u00e1s seguro de que deseas detener el servidor WS? Se desconectar\u00e1n todos los jugadores.',
                                                confirmLabel: 'Detener',
                                              );
                                              if (confirm != true) return;
                                              widget.onStopWs?.call();
                                            },
                                            icon: const Icon(Icons.stop_circle_outlined, size: 16),
                                            label: const Text('Detener', maxLines: 1, overflow: TextOverflow.ellipsis),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kRed,
                                              side: const BorderSide(color: kRed),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 5,
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              SoundService.playClick();
                                              final confirm = await _confirm(
                                                context: context,
                                                title: 'Reiniciar servidor',
                                                message:
                                                    '\u00bfEst\u00e1s seguro de que deseas reiniciar el servidor WS? Se desconectar\u00e1n todos los jugadores temporalmente.',
                                                confirmLabel: 'Reiniciar',
                                              );
                                              if (confirm != true) return;
                                              widget.onReiniciarWs?.call();
                                            },
                                            icon: const Icon(Icons.restart_alt_rounded, size: 16),
                                            label: const Text('Reiniciar', maxLines: 1, overflow: TextOverflow.ellipsis),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kGold,
                                              side: const BorderSide(color: kGold),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (transport.localIp != null && transport.port > 0) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                                        child: Column(
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.wifi_tethering_rounded, color: kGold, size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      SoundService.playClick();
                                                      Clipboard.setData(
                                                        ClipboardData(text: '${transport.localIp}:${transport.port}'),
                                                      );
                                                      NotificationService().show(
                                                        'IP copiada: ${transport.localIp}:${transport.port}',
                                                        backgroundColor: kGreen,
                                                      );
                                                    },
                                                    child: Text(
                                                      'IP: ${transport.localIp}:${transport.port}',
                                                      style: const TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                ),
                                                const Icon(Icons.copy_rounded, color: kTextSecondary, size: 14),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Center(
                                              child: QrImageView(
                                                data: 'ws://${transport.localIp}:${transport.port}',
                                                version: QrVersions.auto,
                                                size: 120,
                                                backgroundColor: Colors.white,
                                                padding: const EdgeInsets.all(6),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Escanea con la app del jugador o comparte la IP',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: kTextSecondary, fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : ElevatedButton.icon(
                                  onPressed: () async {
                                    SoundService.playClick();
                                    final ready = await widget.onEnsureWsReady?.call();
                                    if (ready != true || !context.mounted) return;
                                    await P2PService().startWsServer();
                                    P2PService().setTransport(TransportType.ws);
                                  },
                                  icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                                  label: const Text('Iniciar Servidor WS'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );

    return panel;
  }

  Future<bool?> _confirm({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showGameDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
