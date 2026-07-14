part of '../wallet_screen.dart';

class DiscoveredBanksList extends StatelessWidget {
  final void Function(BleBankDevice bank)? onConnectToBleBank;

  const DiscoveredBanksList({
    super.key,
    this.onConnectToBleBank,
  });

  @override
  Widget build(BuildContext context) {
    final transport = P2PService().bleTransport;

    return ValueListenableBuilder<List<BleBankDevice>>(
      valueListenable: transport.discoveredBanksNotifier,
      builder: (context, banks, _) {
        if (banks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Buscando bancos BLE activos...',
              style: TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bancos disponibles',
                style: TextStyle(
                  color: kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              ...banks.map((bank) {
                final selectedBank =
                    transport.connectedDeviceNameNotifier.value == bank.name;
                final isConnecting = selectedBank &&
                    transport.connectionStatusNotifier.value
                        .startsWith('Conectando');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isConnecting
                        ? null
                        : () {
                            SoundService.playClick();
                            onConnectToBleBank?.call(bank);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue
                            .withValues(alpha: isConnecting ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue
                              .withValues(alpha: isConnecting ? 0.65 : 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isConnecting)
                            const AppSpinner(
                              size: 20,
                              color: Colors.blue,
                            )
                          else
                            const Icon(
                              Icons.account_balance_rounded,
                              color: Colors.blue,
                              size: 20,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bank.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: kTextPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  isConnecting
                                      ? 'Conectando, espera un momento...'
                                      : '${bank.proximityLabel} - ${bank.rssi} dBm',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isConnecting)
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: kTextSecondary,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
