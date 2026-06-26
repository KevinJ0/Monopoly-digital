import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/transports/ble_transport.dart';
import 'package:monopoly_banking/services/transports/nfc_transport.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/network_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _amountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  String _selectedOp = 'payment';
  String _connectedPlayerName = 'Jugador';
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slide;

  final _operations = const [
    _OpOption(id: 'payment', label: 'Cobrar al jugador', icon: Icons.arrow_upward_rounded, color: kRed),
    _OpOption(id: 'receive', label: 'Pagar al jugador', icon: Icons.arrow_downward_rounded, color: kGreen),
    _OpOption(id: 'handshake', label: 'Handshake inicial', icon: Icons.wifi_tethering_rounded, color: kGold),
    _OpOption(id: 'passGo', label: 'Pasar por GO', icon: Icons.flag_rounded, color: kGold),
    _OpOption(id: 'manual', label: 'Intermediario Físico', icon: Icons.handshake_rounded, color: Colors.cyan),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    P2PService().payloadStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'handshake_confirm') {
        final name = payload['name'] as String? ?? 'Jugador';
        _connectedPlayerName = name;
        _toast('✅ $name se ha unido a la partida', kGold);
      }
    }, onError: (e, s) {
      if (mounted) context.showFriendlyError(e, s);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _toast('NFC listo — intenta de nuevo', kGold);
    }
  }

  Future<void> _send() async {
    SoundService.playClick();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _sending = true);
    final dialog = _BankOperationDialogController();
    var dialogOpen = false;

    if (_selectedOp != 'manual') {
      dialogOpen = true;
      _showOperationDialog(dialog).whenComplete(() {
        dialogOpen = false;
      });
      await Future<void>.delayed(Duration.zero);
    }

    try {
      final contactReady = await _waitForBleContactIfNeeded(dialog);
      if (!contactReady) return;

      dialog.update(
        title: _operationWaitTitle(),
        message: _operationWaitMessage(),
      );

      if (_selectedOp == 'handshake') {
        final amountText = _amountCtrl.text.isEmpty ? '2000' : _amountCtrl.text.replaceAll(',', '');
        final amount = double.parse(amountText);
        final session = context.read<SessionProvider>();
        await _sendToConnectedPlayer({
          'type': 'handshake',
          'balance': amount,
          'avatarId': session.avatarId,
          'colorId': session.colorId,
          'gameId': 'monopoly',
          'name': session.name,
        });
        _toast('Handshake enviado con ${formatMoney(amount)}', kGold);
      } else if (_selectedOp == 'passGo') {
        _toast('Enviando Pass GO al jugador conectado...', kGold);
        await _sendToConnectedPlayer({'type': 'passGo'});
        _toast('✅ Pass GO enviado (+${formatMoney(kPassGoAmount)})', kGold);
      } else {
        final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));
        if (_selectedOp == 'receive') {
          final wallet = context.read<WalletController>();
          await _sendToConnectedPlayer({'type': 'payment', 'amount': amount});
          await wallet.subtractFunds(amount);
          _toast('Pago de ${formatMoney(amount)} enviado', kGreen);
        } else {
          final wallet = context.read<WalletController>();
          await _sendToConnectedPlayer({'type': 'charge', 'amount': amount});
          await wallet.addFunds(amount);
          _toast('Cobro de ${formatMoney(amount)} realizado', kRed);
        }
      }
      dialog.complete('Proceso completado con el jugador ${_playerNameLabel()}');
    } catch (e, s) {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        if (e is NfcDisabledException) {
          await _showNfcDisabledDialog();
        } else if (e is TransportUnavailableException) {
          _toast(e.transportName, kRed);
        } else {
          context.showFriendlyError(e, s);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _amountCtrl.clear();
      }
    }
  }

  Future<bool> _waitForBleContactIfNeeded(_BankOperationDialogController dialog) async {
    final transport = P2PService().bleTransport;
    if (!transport.serverActiveNotifier.value || !transport.clientConnectedNotifier.value || transport.contactReadyNotifier.value) {
      return true;
    }

    final completer = Completer<bool>();
    dialog.update(
      title: 'Acerca el jugador al banco',
      message: 'Esperando contacto BLE para iniciar la operación. Pon ambos dispositivos muy cerca.',
    );

    void finish(bool value) {
      if (completer.isCompleted) return;
      completer.complete(value);
    }

    void contactListener() {
      if (transport.contactReadyNotifier.value) {
        finish(true);
      }
    }

    transport.contactReadyNotifier.addListener(contactListener);
    void cancelListener() {
      if (dialog.cancelled.value) finish(false);
    }

    dialog.cancelled.addListener(cancelListener);

    void rssiListener() {
      final rssi = transport.contactRssiNotifier.value;
      if (rssi == null) return;
      dialog.update(
        title: 'Acerca el jugador al banco',
        message: 'Señal actual: $rssi dBm. Acércalo más hasta que marque contacto.',
      );
    }

    transport.contactRssiNotifier.addListener(rssiListener);
    rssiListener();

    final result = await completer.future;
    transport.contactReadyNotifier.removeListener(contactListener);
    transport.contactRssiNotifier.removeListener(rssiListener);
    dialog.cancelled.removeListener(cancelListener);
    return result;
  }

  Future<void> _showOperationDialog(_BankOperationDialogController controller) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<String>(
          valueListenable: controller.title,
          builder: (context, title, _) {
            return ValueListenableBuilder<String>(
              valueListenable: controller.message,
              builder: (context, message, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: controller.completed,
                  builder: (context, completed, _) {
                    return AlertDialog(
                      backgroundColor: kBgCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: completed ? kGreen.withValues(alpha: 0.45) : Colors.blue.withValues(alpha: 0.35),
                        ),
                      ),
                      title: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OperationLoadingVisual(completed: completed),
                          const SizedBox(height: 18),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              message,
                              key: ValueKey(message),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: kTextSecondary,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            SoundService.playClick();
                            if (!completed) {
                              controller.cancelled.value = true;
                            }
                            Navigator.of(ctx).pop();
                          },
                          child: Text(completed ? 'Cerrar' : 'Cancelar'),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ).whenComplete(() {
      if (!controller.completed.value) {
        controller.cancelled.value = true;
      }
    });
  }

  Future<void> _showOperationWaitDialog({
    required String title,
    required String message,
    required VoidCallback onCancel,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Mantén los dispositivos en contacto BLE hasta completar.',
                style: TextStyle(color: kTextSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                SoundService.playClick();
                onCancel();
                Navigator.of(ctx).pop();
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  String _operationWaitTitle() {
    return switch (_selectedOp) {
      'handshake' => 'Esperando handshake inicial',
      'passGo' => 'Esperando Pass GO',
      'receive' => 'Esperando pago al jugador',
      'payment' => 'Esperando cobro al jugador',
      _ => 'Esperando operación',
    };
  }

  String _operationWaitMessage() {
    return switch (_selectedOp) {
      'handshake' => 'Enviando datos iniciales al jugador...',
      'passGo' => 'Enviando recompensa por pasar GO...',
      'receive' => 'Enviando dinero al jugador...',
      'payment' => 'Solicitando cobro al jugador...',
      _ => 'Procesando la operación...',
    };
  }

  String _playerNameLabel() {
    final knownName = _connectedPlayerName.trim();
    if (knownName.isNotEmpty && knownName != 'Jugador') return knownName;
    final name = P2PService().bleTransport.connectedDeviceNameNotifier.value;
    return name.trim().isEmpty ? 'Jugador' : name;
  }

  Future<void> _sendToConnectedPlayer(Map<String, dynamic> payload) async {
    final transport = P2PService().bleTransport;
    P2PService().setTransport(TransportType.ble);

    if (!transport.serverActiveNotifier.value) {
      throw TransportUnavailableException(
        'Servidor BLE apagado. Vuelve a la pantalla principal del banco para activarlo.',
      );
    }

    if (!transport.clientConnectedNotifier.value) {
      throw TransportUnavailableException(
        'No hay jugador conectado por BLE. Abre la app del jugador y conéctalo al banco.',
      );
    }

    if (!transport.contactReadyNotifier.value) {
      final rssi = transport.contactRssiNotifier.value;
      throw TransportUnavailableException(
        rssi == null
            ? 'Acerca el jugador al banco para simular contacto NFC.'
            : 'Jugador fuera de contacto BLE ($rssi dBm). Acerca los dispositivos.',
      );
    }

    await P2PService().sendPayload(payload);
  }

  Future<void> _showNfcDisabledDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NFC desactivado'),
        content: const Text('Para usar la app necesitas NFC. ¿Quieres activarlo ahora?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _toast('Abriendo ajustes de NFC...', kGold);
      await Future.delayed(const Duration(milliseconds: 600));
      final nfcTransport = P2PService().transports[TransportType.nfc] as NfcTransport?;
      await nfcTransport?.openNfcSettings();
    } else {
      _toast('NFC necesario para continuar', kRed);
    }
  }

  void _toast(String msg, Color color) {
    NotificationService().show(msg, backgroundColor: color);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kTextSecondary),
          onPressed: () {
            SoundService.playClick();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Panel del Banco',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _slideCtrl,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.viewPaddingOf(context).bottom + 128,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AnimatedEntry(
                        delay: Duration(milliseconds: 100),
                        child: _BankHeader(),
                      ),
                      const SizedBox(height: 24),
                      AnimatedEntry(
                        delay: const Duration(milliseconds: 200),
                        child: _buildOpSelector(),
                      ),
                      const SizedBox(height: 24),
                      if (_selectedOp == 'manual')
                        _buildManualTransferInterface()
                      else ...[
                        if (_selectedOp != 'passGo')
                          AnimatedEntry(
                            delay: const Duration(milliseconds: 300),
                            child: _buildAmountField(),
                          ),
                        const SizedBox(height: 28),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 400),
                          child: _buildQuickAmounts(),
                        ),
                        const SizedBox(height: 32),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 500),
                          child: _buildSendButton(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualTransferInterface() {
    return StreamBuilder<TransferState>(
      stream: BancoServer().stateStream,
      initialData: BancoServer().state,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          decoration: BoxDecoration(
            color: kBgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            children: [
              _buildStateAnimation(state),
              const SizedBox(height: 24),
              Text(
                _getStateLabel(state),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _getStateSublabel(state),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary, fontSize: 14),
              ),
              if (state == TransferState.idle) ...[
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    SoundService.playClick();
                    BancoServer().start();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Iniciar Servidor de Banco', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStateAnimation(TransferState state) {
    if (state == TransferState.idle) {
      return const Icon(Icons.power_settings_new_rounded, size: 80, color: kBorder);
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: CircularProgressIndicator(
            value: state == TransferState.holding ? 1.0 : null,
            strokeWidth: 8,
            color: _getStateColor(state),
          ),
        ),
        Icon(_getStateIcon(state), size: 40, color: _getStateColor(state)),
      ],
    );
  }

  String _getStateLabel(TransferState state) {
    switch (state) {
      case TransferState.idle:
        return 'Servidor de Banco Apagado';
      case TransferState.listening:
        return 'Banco Activo';
      case TransferState.waitingSender:
        return 'Esperando Emisor';
      case TransferState.holding:
        return 'Dinero Retenido';
      case TransferState.waitingReceiver:
        return 'Esperando Receptor';
    }
  }

  String _getStateSublabel(TransferState state) {
    switch (state) {
      case TransferState.idle:
        return 'Inicia el servidor para transacciones manuales';
      case TransferState.listening:
        return 'Esperando transferencia de un jugador...';
      case TransferState.waitingSender:
        return 'El emisor debe acercar el dispositivo';
      case TransferState.holding:
        return 'Validando saldo y procesando débito...';
      case TransferState.waitingReceiver:
        return 'Retención completa. Receptor acerque dispositivo';
    }
  }

  Color _getStateColor(TransferState state) {
    switch (state) {
      case TransferState.listening:
        return Colors.cyan;
      case TransferState.waitingSender:
        return kRed;
      case TransferState.holding:
        return kGold;
      case TransferState.waitingReceiver:
        return kGreen;
      default:
        return kBorder;
    }
  }

  IconData _getStateIcon(TransferState state) {
    switch (state) {
      case TransferState.listening:
        return Icons.sensors_rounded;
      case TransferState.waitingSender:
        return Icons.upload_rounded;
      case TransferState.holding:
        return Icons.lock_clock_rounded;
      case TransferState.waitingReceiver:
        return Icons.download_rounded;
      default:
        return Icons.error;
    }
  }

  Widget _buildOpSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPERACIÓN',
          style: TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        ...(_operations.map((op) => _buildOpTile(op))),
      ],
    );
  }

  Widget _buildOpTile(_OpOption op) {
    final selected = _selectedOp == op.id;
    return GestureDetector(
      onTap: () {
        SoundService.playClick();
        setState(() => _selectedOp = op.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? op.color.withValues(alpha: 0.12) : kBgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? op.color : kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(op.icon, color: selected ? op.color : kTextSecondary, size: 20),
            const SizedBox(width: 12),
            Text(
              op.label,
              style: TextStyle(
                color: selected ? op.color : kTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: op.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MONTO',
          style: TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _amountCtrl,
          onTap: () => SoundService.playClick(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: const TextStyle(color: kGreen, fontSize: 24, fontWeight: FontWeight.w700),
            hintText: '0',
            hintStyle: const TextStyle(color: kBorder, fontSize: 24),
            filled: true,
            fillColor: kBgCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kGreen, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kRed),
            ),
          ),
          validator: (v) {
            if (_selectedOp == 'handshake' && (v == null || v.isEmpty)) {
              return null;
            }
            if (v == null || v.isEmpty) return 'Ingresa un monto';
            final n = double.tryParse(v.replaceAll(',', ''));
            if (n == null || n <= 0) return 'Monto inválido';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildQuickAmounts() {
    if (_selectedOp == 'handshake' || _selectedOp == 'passGo') {
      return const SizedBox();
    }
    const presets = [50, 100, 200, 500, 1000, 2000];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((p) {
        return GestureDetector(
          onTap: () {
            SoundService.playClick();
            _amountCtrl.text = '$p';
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Text(
              formatMoney(p),
              style: const TextStyle(color: kTextSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSendButton() {
    final op = _operations.firstWhere((o) => o.id == _selectedOp);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : Icon(op.icon),
          label: Text(
            _sending ? 'Enviando...' : op.label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: op.color,
            foregroundColor: op.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

class _BankOperationDialogController {
  final title = ValueNotifier<String>('Preparando operación');
  final message = ValueNotifier<String>('Esperando contacto BLE...');
  final completed = ValueNotifier<bool>(false);
  final cancelled = ValueNotifier<bool>(false);

  void update({
    required String title,
    required String message,
  }) {
    if (completed.value || cancelled.value) return;
    this.title.value = title;
    this.message.value = message;
  }

  void complete(String message) {
    completed.value = true;
    title.value = 'Proceso completado';
    this.message.value = message;
  }
}

class _OperationLoadingVisual extends StatefulWidget {
  const _OperationLoadingVisual({required this.completed});

  final bool completed;

  @override
  State<_OperationLoadingVisual> createState() => _OperationLoadingVisualState();
}

class _OperationLoadingVisualState extends State<_OperationLoadingVisual> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      child: widget.completed
          ? Container(
              key: const ValueKey('completed'),
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreen.withValues(alpha: 0.14),
                border: Border.all(color: kGreen.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: kGreen.withValues(alpha: 0.28),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: kGreen,
                size: 58,
              ),
            )
          : SizedBox(
              key: const ValueKey('waiting'),
              width: 136,
              height: 136,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  final pulse = _pulseCtrl.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      _PulseRing(progress: pulse, delay: 0),
                      _PulseRing(progress: pulse, delay: 0.33),
                      _PulseRing(progress: pulse, delay: 0.66),
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.withValues(alpha: 0.95),
                              kGold.withValues(alpha: 0.88),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Transform.scale(
                          scale: 1 + (0.06 * math.sin(pulse * math.pi * 2)),
                          child: const Icon(
                            Icons.bluetooth_searching_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress, required this.delay});

  final double progress;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final adjusted = (progress + delay) % 1;
    final size = 72 + (adjusted * 58);
    final opacity = (1 - adjusted).clamp(0.0, 1.0) * 0.32;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.blue.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}

class _BankHeader extends StatelessWidget {
  const _BankHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_rounded, color: kGold, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Banca Central',
                  style: TextStyle(color: kGold, fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  'Gestiona el capital de los jugadores',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BleServerPanel extends StatelessWidget {
  const _BleServerPanel();

  Future<bool> _ensureBleReady(BuildContext context, BleTransport transport) async {
    var status = await transport.refreshAvailability();
    if (status == BleAvailabilityStatus.ready) return true;
    if (!context.mounted) return false;

    if (status == BleAvailabilityStatus.noHardware) {
      _showMessage(context, 'Este dispositivo no tiene Bluetooth LE disponible.');
      return false;
    }

    if (status == BleAvailabilityStatus.missingPermissions) {
      final allow = await _confirm(
        context,
        title: 'Permisos de Bluetooth',
        message: 'Para activar el servidor BLE del banco necesito permisos de Bluetooth. ¿Quieres permitirlos ahora?',
        confirmLabel: 'Permitir',
      );
      if (allow != true || !context.mounted) return false;

      await transport.requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));
      status = await transport.refreshAvailability();
      if (status == BleAvailabilityStatus.ready) return true;
      if (status == BleAvailabilityStatus.bluetoothOff && context.mounted) {
        return _askToOpenBleSettings(context, transport);
      }
      if (context.mounted) {
        _showMessage(context, 'Permisos de Bluetooth pendientes. Revisa los permisos de la app e intenta de nuevo.');
      }
      return false;
    }

    if (status == BleAvailabilityStatus.bluetoothOff) {
      return _askToOpenBleSettings(context, transport);
    }

    _showMessage(context, 'No pude verificar Bluetooth. Revisa los ajustes e intenta de nuevo.');
    return false;
  }

  Future<bool> _askToOpenBleSettings(BuildContext context, BleTransport transport) async {
    final open = await _confirm(
      context,
      title: 'Bluetooth apagado',
      message: 'Para usar el banco por BLE debes activar Bluetooth. ¿Quieres abrir los ajustes?',
      confirmLabel: 'Abrir ajustes',
    );
    if (open == true && context.mounted) {
      await transport.openBleSettings();
    }
    return false;
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
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

  void _showMessage(BuildContext context, String message) {
    NotificationService().show(message, backgroundColor: kRed);
  }

  @override
  Widget build(BuildContext context) {
    final transport = P2PService().bleTransport;

    return ValueListenableBuilder<bool>(
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
                        ? 'SERVIDOR BLE ACTIVO'
                        : 'SERVIDOR BLE';
                final subtitle = status.isNotEmpty
                    ? status
                    : active
                        ? 'Esperando que un jugador se conecte...'
                        : 'Activa el servidor para recibir jugadores por Bluetooth';
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: active ? accent.withValues(alpha: 0.08) : kBgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? accent.withValues(alpha: 0.4) : kBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
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
                              color: active ? accent : kBorder,
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.6),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: active
                            ? OutlinedButton.icon(
                                onPressed: () {
                                  SoundService.playClick();
                                  transport.stopServer();
                                },
                                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                                label: const Text('Detener Servidor BLE'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kRed,
                                  side: const BorderSide(color: kRed),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () async {
                                  SoundService.playClick();
                                  final ready = await _ensureBleReady(context, transport);
                                  if (!ready || !context.mounted) return;
                                  await transport.startServer();
                                  P2PService().setTransport(TransportType.ble);
                                },
                                icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                                label: const Text('Iniciar Servidor BLE'),
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
    );
  }
}

class _OpOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const _OpOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}
