import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';

class TransportSelector extends StatelessWidget {
  const TransportSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final p2p = P2PService();

    return ValueListenableBuilder<TransportType>(
      valueListenable: p2p.typeNotifier,
      builder: (context, current, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: kBgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              _Option(
                icon: Icons.nfc_rounded,
                label: 'NFC',
                selected: current == TransportType.nfc,
                enabled: p2p.transports[TransportType.nfc]?.isEnabled ?? false,
                onTap: () {
                  SoundService.playClick();
                  p2p.setTransport(TransportType.nfc);
                },
              ),
              _Option(
                icon: Icons.bluetooth_rounded,
                label: 'BT',
                selected: current == TransportType.ble,
                enabled: true,
                onTap: () {
                  SoundService.playClick();
                  p2p.setTransport(TransportType.ble);
                },
              ),
              _Option(
                icon: Icons.wifi_rounded,
                label: 'WiFi',
                selected: current == TransportType.wifi,
                enabled: p2p.transports[TransportType.wifi]?.isEnabled ?? false,
                onTap: () {
                  SoundService.playClick();
                  p2p.setTransport(TransportType.wifi);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                selected ? kGold.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected
                    ? kGold
                    : enabled
                        ? kTextSecondary
                        : Colors.white12,
                size: 20,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? kGold
                      : enabled
                          ? kTextSecondary
                          : Colors.white12,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
