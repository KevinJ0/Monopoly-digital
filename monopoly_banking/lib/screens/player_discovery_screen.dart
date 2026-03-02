import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/network_service.dart';
import 'package:monopoly_banking/providers/session_provider.dart';

class PlayerDiscoveryScreen extends StatelessWidget {
  const PlayerDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionProvider>();

    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        title: const Text('Descubrir Jugadores', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<List<dynamic>>(
        stream: JugadorClient().playersStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kGold),
                  SizedBox(height: 20),
                  Text('Buscando jugadores en la red...', style: TextStyle(color: kTextSecondary)),
                ],
              ),
            );
          }

          final players = snapshot.data!.where((p) => p['USUARIOID'] != session.name).toList();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: players.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final player = players[index];
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showTransferDialog(context, player, session.name),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kBgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(player['avatar'] ?? '👤', style: const TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player['USUARIOID'],
                                style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Saldo: \$${player['TREVNOT']}',
                                style: const TextStyle(color: kTextSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: kBorder, size: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showTransferDialog(BuildContext context, dynamic player, String myId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kBgCard,
        title: Text('Transferir a ${player['USUARIOID']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Monto a transferir',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(controller.text) ?? 0;
              if (amount > 0) {
                JugadorClient().requestTransfer(player['USUARIOID'], amount, myId);
                Navigator.pop(context);
                Navigator.pop(context);
              }
            },
            child: const Text('Solicitar al Banco'),
          ),
        ],
      ),
    );
  }
}
