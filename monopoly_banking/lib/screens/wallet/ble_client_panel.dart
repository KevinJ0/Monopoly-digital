part of '../wallet_screen.dart';

class BleClientPanel extends StatelessWidget {
  final Color color;
  final bool bleScanning;
  final VoidCallback? onStopBleClient;
  final VoidCallback? onStartBleClient;
  final void Function(BleBankDevice bank)? onConnectToBleBank;

  const BleClientPanel({
    super.key,
    required this.color,
    required this.bleScanning,
    this.onStopBleClient,
    this.onStartBleClient,
    this.onConnectToBleBank,
  });

  @override
  Widget build(BuildContext context) {
    final transport = P2PService().bleTransport;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: transport.clientConnectedNotifier,
        builder: (context, connected, _) {
          return ValueListenableBuilder<String>(
            valueListenable: transport.connectionStatusNotifier,
            builder: (context, status, _) {
              return ValueListenableBuilder<String>(
                valueListenable: transport.connectedDeviceNameNotifier,
                builder: (context, _, __) {
                  final connecting = status.startsWith('Conectando') ||
                      status.startsWith('Preparando');
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: connected
                          ? color.withValues(alpha: 0.08)
                          : kBgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: connected
                            ? color.withValues(alpha: 0.5)
                            : connecting
                                ? Colors.blue.withValues(alpha: 0.4)
                                : bleScanning
                                    ? Colors.blue.withValues(alpha: 0.4)
                                    : kBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connected
                                  ? Icons.bluetooth_connected_rounded
                                  : connecting
                                      ? Icons.bluetooth_searching_rounded
                                      : bleScanning
                                          ? Icons.bluetooth_searching_rounded
                                          : Icons.bluetooth_rounded,
                              color: connected
                                  ? color
                                  : connecting
                                      ? Colors.blue
                                      : bleScanning
                                          ? Colors.blue
                                          : kTextSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    connected
                                        ? 'CONECTADO AL BANCO'
                                        : connecting
                                            ? 'CONECTANDO AL BANCO...'
                                            : bleScanning
                                                ? 'CONECTANDO POR BLE...'
                                                : 'BLUETOOTH',
                                    style: TextStyle(
                                      color: connected
                                          ? color
                                          : connecting
                                              ? Colors.blue
                                              : bleScanning
                                                  ? Colors.blue
                                                  : kTextSecondary,
                                      fontSize: 11,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (status.isNotEmpty)
                                    Text(
                                      status,
                                      style: const TextStyle(
                                        color: kTextSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected
                                    ? color
                                    : connecting
                                        ? Colors.blue
                                        : bleScanning
                                            ? Colors.blue
                                            : kBorder,
                                boxShadow: (connected ||
                                        bleScanning ||
                                        connecting)
                                    ? [
                                        BoxShadow(
                                          color:
                                              (connected ? color : Colors.blue)
                                                  .withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: connected || bleScanning || connecting
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    SoundService.playClick();
                                    onStopBleClient?.call();
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_disabled_rounded,
                                      size: 16),
                                  label: Text(connected
                                      ? 'Desconectar del Banco'
                                      : 'Cancelar conexión'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kRed,
                                    side: const BorderSide(color: kRed),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.withValues(alpha: 0.9),
                                        Colors.blue.withValues(alpha: 0.6),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        SoundService.playClick();
                                        onStartBleClient?.call();
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.bluetooth_searching_rounded,
                                              size: 18,
                                              color: Colors.white
                                                  .withValues(alpha: 0.9),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Conectar por BLE',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        if (!connected && (bleScanning || connecting))
                          DiscoveredBanksList(
                            onConnectToBleBank: onConnectToBleBank,
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
  }
}
