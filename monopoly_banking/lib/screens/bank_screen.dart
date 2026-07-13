import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/transports/ble_transport.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/app_audit_logger.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/widgets/player_info_widget.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _amountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  bool _transferHoldDialogOpen = false;
  String _selectedOp = 'payment';
  String _connectedPlayerName = 'Jugador';
  StreamSubscription<Map<String, dynamic>>? _payloadSub;
  final Map<String, Completer<Map<String, dynamic>>> _pendingDeliveryAcks = {};
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slide;

  final _operations = const [
    _OpOption(
        id: 'payment',
        label: 'Cobrar al jugador',
        icon: Icons.arrow_upward_rounded,
        color: kRed),
    _OpOption(
        id: 'receive',
        label: 'Pagar al jugador',
        icon: Icons.arrow_downward_rounded,
        color: kGreen),
    _OpOption(
        id: 'passGo',
        label: 'Pasar por GO',
        icon: Icons.flag_rounded,
        color: kGold),
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

    _payloadSub = P2PService().payloadStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'bank_state_ack') {
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null) {
          final completer = _pendingDeliveryAcks[bankTxId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload);
          }
        }
        return;
      }
      if (payload['type'] == 'handshake_confirm') {
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null) {
          final completer = _pendingDeliveryAcks[bankTxId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload);
          }
        }
      }
      if (payload['type'] == 'handshake_confirm' ||
          payload['type'] == 'ble_identity') {
        final name = payload['name'] as String? ?? 'Jugador';
        _connectedPlayerName = name;
        if (payload['type'] == 'ble_identity') {
          final account = BankLedgerService().accountFor(name);
          final installationId =
              (payload['deviceInstallationId'] as String?) ?? '';
          final isReturningPlayer = account != null &&
              !account.bankrupt &&
              account.deviceInstallationId.isNotEmpty &&
              account.deviceInstallationId == installationId;
          if (isReturningPlayer) {
            final bleDeviceId = payload['_bleDeviceId'] as String?;
            if (bleDeviceId != null && bleDeviceId.isNotEmpty) {
              P2PService().bleTransport.markPlayerActive(bleDeviceId);
            }
          }
          NotificationService().show(
            isReturningPlayer
                ? '$name se reconectó a la partida'
                : '$name se conectó al banco',
            backgroundColor: kGreen,
            duration: const Duration(seconds: 4),
            dedupeKey: 'ble-connected:${payload['_bleDeviceId'] ?? name}',
          );
        }
      }
    }, onError: (e, s) {
      if (mounted) context.showFriendlyError(e, s);
    });
  }

  @override
  void dispose() {
    for (final completer in _pendingDeliveryAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Pantalla del banco cerrada'));
      }
    }
    _pendingDeliveryAcks.clear();
    WidgetsBinding.instance.removeObserver(this);
    _payloadSub?.cancel();
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
    AppAuditLogger.instance.event('BANK_OP', '_send start',
        data: {'op': _selectedOp, 'amount': _amountCtrl.text});

    setState(() => _sending = true);
    final dialog = _BankOperationDialogController(
      transportType: P2PService().currentType,
    );
    var dialogOpen = false;

    dialogOpen = true;
    _showOperationDialog(dialog).whenComplete(() {
      dialogOpen = false;
    });
    await Future<void>.delayed(Duration.zero);

    try {
      if (dialog.transportType == TransportType.ble &&
          !P2PService().bleTransport.clientConnectedNotifier.value) {
        await _failOperationDialog(
          dialog,
          'Sin jugador conectado',
          'No hay ningún jugador conectado por BLE. Abre la app del jugador, conéctalo al banco y vuelve a intentar.',
          icon: Icons.bluetooth_disabled_rounded,
          color: Colors.orange,
        );
        return;
      }
      if (dialog.transportType == TransportType.ble &&
          !await _waitForBlePlayerReady(dialog)) {
        await _failOperationDialog(
          dialog,
          'Jugador no disponible',
          'El dispositivo aparece conectado, pero no terminó de preparar el canal BLE. Mantén ambas aplicaciones abiertas e intenta nuevamente.',
          icon: Icons.phonelink_off_rounded,
          color: Colors.orange,
        );
        return;
      }

      final contactReady = await _waitForBleContactIfNeeded(dialog);
      if (!contactReady) return;

      dialog.update(
        title: _operationWaitTitle(),
        message: _operationWaitMessage(),
      );

      final ledger = BankLedgerService();
      final targetPlayer = _contactPlayer();
      final playerId = targetPlayer?.displayName;
      if (playerId == null || playerId.isEmpty) {
        throw const BankLedgerException(
          'No se pudo identificar al jugador. Conéctalo por BLE primero.',
        );
      }
      final deviceInstallationId = targetPlayer?.deviceInstallationId ?? '';
      final playerIsActive = targetPlayer?.playing ?? false;
      if (deviceInstallationId.isEmpty) {
        await _failOperationDialog(
          dialog,
          'Identidad pendiente',
          'Espera un momento mientras el banco verifica la identidad del dispositivo.',
          icon: Icons.phonelink_lock_rounded,
          color: Colors.orange,
        );
        return;
      }

      if (_selectedOp == 'passGo') {
        if (!playerIsActive) {
          await _failOperationDialog(
            dialog,
            'Handshake requerido',
            'El jugador debe recibir el handshake inicial antes de jugar.',
          );
          return;
        }
        final result = await ledger.passGo(playerId);
          await _sendToConnectedPlayer(result.toClientPayload());
          SoundService.playFanfare();
          HapticFeedback.vibrate();
          NotificationService().show('$playerId pasó por GO: +${formatMoney(200)}',
              backgroundColor: kGold);
      } else {
        if (!playerIsActive) {
          await _failOperationDialog(
            dialog,
            'Handshake requerido',
            'El jugador debe recibir el handshake inicial antes de jugar.',
          );
          return;
        }
        final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));
        if (_selectedOp == 'receive') {
          final result = await ledger.credit(
            playerId,
            amount,
            type: 'payment',
            counterpartyId: 'Banco',
          );
          await _sendToConnectedPlayer(result.toClientPayload());
          SoundService.playSuccess();
          HapticFeedback.mediumImpact();
          NotificationService().show(
              'Pagado ${formatMoney(amount)} a $playerId',
              backgroundColor: Colors.green.shade700);
        } else {
          final account = ledger.accountFor(playerId);
          if (account == null) {
            throw const BankLedgerException(
              'El jugador necesita completar el handshake inicial.',
            );
          }
          if (amount > account.balance) {
            final proceed = await _confirmBankruptcy(
              playerId: playerId,
              availableBalance: account.balance,
              chargeAmount: amount,
            );
            if (proceed != true) {
              await _failOperationDialog(
                dialog,
                'Cobro cancelado',
                'El jugador conserva su saldo y continúa activo en la partida.',
                icon: Icons.shield_outlined,
                color: Colors.orange,
              );
              return;
            }

            final result = await ledger.markBankrupt(
              playerId,
              attemptedCharge: amount,
              deviceInstallationId: deviceInstallationId,
            );
            await _sendToConnectedPlayer(result.toClientPayload());
            SoundService.playSadTrombone();
            HapticFeedback.heavyImpact();
            NotificationService().show(
                '$playerId en bancarrota. Expulsado de la partida.',
                backgroundColor: kRed);
            if (targetPlayer != null) {
              P2PService().bleTransport.markPlayerInactive(targetPlayer.id);
            }
            dialog.complete(
              '$playerId fue declarado en bancarrota y expulsado de la partida.',
            );
            return;
          }
          final result = await ledger.debit(
            playerId,
            amount,
            type: 'charge',
            counterpartyId: 'Banco',
          );
          await _sendToConnectedPlayer(result.toClientPayload());
          SoundService.playSadTrombone();
          HapticFeedback.heavyImpact();
          NotificationService().show(
              'Cobrado ${formatMoney(amount)} a $playerId',
              backgroundColor: Colors.orange.shade800);
        }
      }
      dialog
          .complete('Proceso completado con el jugador ${_playerNameLabel()}');
    } catch (e, s) {
      AppAuditLogger.instance.event('BANK_OP', '_send_error',
          data: {'op': _selectedOp, 'error': e.toString()},
          error: e,
          stack: s);
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        if (e is TransportUnavailableException) {
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

  Future<void> _failOperationDialog(
    _BankOperationDialogController dialog,
    String title,
    String message, {
    IconData icon = Icons.close_rounded,
    Color color = kRed,
  }) async {
    dialog.fail(title: title, message: message, icon: icon, color: color);
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  Future<bool?> _confirmBankruptcy({
    required String playerId,
    required double availableBalance,
    required double chargeAmount,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kBgCard,
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: kRed,
          size: 54,
        ),
        title: const Text(
          'Riesgo de bancarrota',
          textAlign: TextAlign.center,
        ),
        content: Text(
          '$playerId dispone de ${formatMoney(availableBalance)}, pero el cobro es de ${formatMoney(chargeAmount)}. '
          'Si continúas, el jugador perderá la partida y este dispositivo quedará bloqueado hasta que cierres la sesión del banco.\n\n'
          '¿Deseas declarar al jugador en bancarrota?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kTextSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.gavel_rounded),
            label: const Text('Declarar bancarrota'),
          ),
        ],
      ),
    );
  }

  Future<bool> _waitForBlePlayerReady(
      _BankOperationDialogController dialog) async {
    final notifier = P2PService().bleTransport.connectedPlayersNotifier;

    bool hasReadyPlayer() => notifier.value.any(
          (player) =>
              player.subscribed &&
              player.name.trim().isNotEmpty &&
              player.deviceInstallationId.trim().isNotEmpty,
        );

    if (hasReadyPlayer()) return true;

    dialog.update(
      title: 'Preparando conexión',
      message: 'Esperando que el jugador complete el canal BLE...',
    );
    final completer = Completer<bool>();

    void finish(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    void playerListener() {
      if (hasReadyPlayer()) finish(true);
    }

    void cancelListener() {
      if (dialog.cancelled.value) finish(false);
    }

    notifier.addListener(playerListener);
    dialog.cancelled.addListener(cancelListener);
    final timeout = Timer(const Duration(seconds: 8), () => finish(false));
    playerListener();

    final result = await completer.future;
    timeout.cancel();
    notifier.removeListener(playerListener);
    dialog.cancelled.removeListener(cancelListener);
    return result;
  }

  Future<bool> _waitForBleContactIfNeeded(
      _BankOperationDialogController dialog) async {
    if (dialog.transportType != TransportType.ble) return true;
    final transport = P2PService().bleTransport;
    if (!transport.serverActiveNotifier.value ||
        !transport.clientConnectedNotifier.value) {
      return true;
    }

    // Resetear todo el estado de contacto para forzar nueva verificación
    transport.contactReadyNotifier.value = false;
    transport.contactRssiNotifier.value = null;

    // Resetear contacto de TODOS los jugadores en la lista
    final current = transport.connectedPlayersNotifier.value;
    final reset = <BleConnectedPlayer>[];
    for (final player in current) {
      if (player.contactReady) {
        reset.add(player.copyWith(contactReady: false));
      } else {
        reset.add(player);
      }
    }
    transport.connectedPlayersNotifier.value = reset;

    final completer = Completer<bool>();
    dialog.update(
      title: 'Acerca el jugador al banco',
      message: 'Acerca los dispositivos para ejecutar esta operación.',
    );

    void finish(bool value) {
      if (completer.isCompleted) return;
      completer.complete(value);
    }

    void contactListener() {
      if (_hasBleContact(transport)) {
        finish(true);
      }
    }

    transport.contactReadyNotifier.addListener(contactListener);
    transport.connectedPlayersNotifier.addListener(contactListener);
    void cancelListener() {
      if (dialog.cancelled.value) finish(false);
    }

    dialog.cancelled.addListener(cancelListener);

    void rssiListener() {
      final rssi =
          _closestBleRssi(transport) ?? transport.contactRssiNotifier.value;
      if (rssi == null) return;
      dialog.update(
        title: 'Acerca el jugador al banco',
        message: 'Señal actual: $rssi dBm. Acerca más los dispositivos.',
      );
    }

    transport.contactRssiNotifier.addListener(rssiListener);
    transport.connectedPlayersNotifier.addListener(rssiListener);
    contactListener();
    rssiListener();

    final timeout = Timer(const Duration(seconds: 15), () => finish(false));

    final result = await completer.future;
    timeout.cancel();
    transport.contactReadyNotifier.removeListener(contactListener);
    transport.connectedPlayersNotifier.removeListener(contactListener);
    transport.contactRssiNotifier.removeListener(rssiListener);
    transport.connectedPlayersNotifier.removeListener(rssiListener);
    dialog.cancelled.removeListener(cancelListener);
    return result;
  }

  BleConnectedPlayer? _contactPlayer() {
    final players = P2PService().bleTransport.connectedPlayersNotifier.value;
    final inContact = players
        .where((player) => player.subscribed && player.contactReady)
        .toList();
    if (inContact.isEmpty) return null;
    inContact.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return inContact.first;
  }

  bool _hasBleContact(BleTransport transport) {
    if (transport.contactReadyNotifier.value) return true;
    return transport.connectedPlayersNotifier.value.any(
      (player) => player.subscribed && player.contactReady,
    );
  }

  int? _closestBleRssi(BleTransport transport) {
    final values = transport.connectedPlayersNotifier.value
        .where((player) => player.subscribed && player.rssi != null)
        .map((player) => player.rssi!)
        .toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => b.compareTo(a));
    return values.first;
  }

  Future<void> _handleTransferHoldRequest(Map<String, dynamic> payload) async {
    if (_transferHoldDialogOpen || !mounted) return;

    final rawAmount = payload['amount'] as num?;
    final amount = rawAmount?.toDouble() ?? 0;
    if (amount <= 0 || !amount.isFinite) return;

    final fromName = ((payload['fromPlayerId'] as String?) ??
            (payload['fromName'] as String?) ??
            'Jugador')
        .trim();

    _transferHoldDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var delivering = false;
        var completed = false;
        var status =
            'Acerca el celular del jugador que recibirá el dinero y pulsa entregar.';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> deliver() async {
              if (delivering || completed) return;
              setDialogState(() {
                delivering = true;
                status = 'Esperando contacto del jugador receptor...';
              });

              final receiver = await _waitForTransferReceiver();
              if (receiver == null) {
                if (!ctx.mounted) return;
                setDialogState(() {
                  delivering = false;
                  status =
                      'No detecté un jugador en contacto. Acércalo e intenta de nuevo.';
                });
                return;
              }

              try {
                P2PService().setTransport(TransportType.ble);
                await P2PService().sendPayload({
                  'type': 'payment',
                  'amount': amount,
                  'targetPlayerId': receiver.displayName,
                  'transferFrom': fromName,
                });
                if (!ctx.mounted) return;
                setDialogState(() {
                  delivering = false;
                  completed = true;
                  status =
                      'Proceso completado con el jugador ${receiver.displayName}.';
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                });
              } catch (e, s) {
                if (!mounted || !ctx.mounted) return;
                context.showFriendlyError(e, s);
                setDialogState(() {
                  delivering = false;
                  status = 'No pude entregar el dinero. Intenta de nuevo.';
                });
              }
            }

            return AlertDialog(
              backgroundColor: kBgCard,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: completed
                      ? kGreen.withValues(alpha: 0.45)
                      : kGold.withValues(alpha: 0.35),
                ),
              ),
              title: Text(
                completed ? 'Transferencia completada' : 'Dinero retenido',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 300,
                height: 226,
                child: Column(
                  children: [
                    Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.account_balance_wallet_rounded,
                      color: completed ? kGreen : kGold,
                      size: 72,
                    ),
                    Text(
                      formatMoney(amount),
                      style: const TextStyle(
                        color: kGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'De: ${fromName.isEmpty ? 'Jugador' : fromName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Text(
                          status,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kTextSecondary,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!completed)
                  TextButton(
                    onPressed: delivering
                        ? null
                        : () {
                            SoundService.playClick();
                            Navigator.of(ctx).pop();
                          },
                    child: const Text('Cerrar'),
                  ),
                SizedBox(
                  width: completed ? double.infinity : 150,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: completed || delivering ? null : deliver,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: completed ? kGreen : kGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: delivering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Icon(completed
                            ? Icons.check_rounded
                            : Icons.touch_app_rounded),
                    label: Text(
                      completed ? 'Completado' : 'Entregar',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      _transferHoldDialogOpen = false;
    });
  }

  Future<BleConnectedPlayer?> _waitForTransferReceiver() async {
    final transport = P2PService().bleTransport;
    final current = _currentTransferReceiver(transport);
    if (current != null) return current;

    final completer = Completer<BleConnectedPlayer?>();
    Timer? timeout;
    late VoidCallback listener;

    void finish(BleConnectedPlayer? player) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      transport.connectedPlayersNotifier.removeListener(listener);
      completer.complete(player);
    }

    listener = () {
      final player = _currentTransferReceiver(transport);
      if (player != null) finish(player);
    };

    transport.connectedPlayersNotifier.addListener(listener);
    timeout = Timer(const Duration(seconds: 15), () => finish(null));
    return completer.future;
  }

  BleConnectedPlayer? _currentTransferReceiver(BleTransport transport) {
    for (final player in transport.connectedPlayersNotifier.value) {
      if (player.subscribed && player.playing) {
        return player;
      }
    }
    for (final player in transport.connectedPlayersNotifier.value) {
      if (player.subscribed) return player;
    }
    return null;
  }

  Future<void> _showOperationDialog(_BankOperationDialogController controller) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var autoCloseScheduled = false;

        return PopScope(
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
                      return ValueListenableBuilder<bool>(
                        valueListenable: controller.failed,
                        builder: (context, failed, _) {
                          final finished = completed || failed;
                          if (finished && !autoCloseScheduled) {
                            autoCloseScheduled = true;
                            Future.delayed(
                              Duration(seconds: completed ? 3 : 2),
                              () {
                                if (ctx.mounted && Navigator.of(ctx).canPop()) {
                                  Navigator.of(ctx).pop();
                                }
                              },
                            );
                          }

                          return AlertDialog(
                            insetPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 24,
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 10),
                            backgroundColor: kBgCard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: completed
                                    ? kGreen.withValues(alpha: 0.45)
                                    : failed
                                        ? controller.failedColor
                                            .withValues(alpha: 0.45)
                                        : Colors.blue
                                            .withValues(alpha: 0.35),
                              ),
                            ),
                            title: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: Center(
                                child: Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(
                                    color: kTextPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            content: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 340,
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * 0.55,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 136,
                                    height: 136,
                                    child: Center(
                                      child: _OperationLoadingVisual(
                                        completed: completed,
                                        failed: failed,
                                        transportType: controller.transportType,
                                        failedIcon: controller.failedIcon,
                                        failedColor: controller.failedColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: Center(
                                        child: AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 220),
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
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: finished
                                    ? ElevatedButton(
                                        onPressed: () {
                                          SoundService.playClick();
                                          Navigator.of(ctx).pop();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: completed
                                              ? kGreen
                                              : controller.failedColor,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: const Text(
                                          'Cerrar',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: () {
                                          SoundService.playClick();
                                          controller.cancelled.value = true;
                                          Navigator.of(ctx).pop();
                                        },
                                        child: const Text('Cancelar'),
                                      ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (!controller.completed.value && !controller.failed.value) {
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
      'passGo' => 'Esperando Pass GO',
      'receive' => 'Esperando pago al jugador',
      'payment' => 'Esperando cobro al jugador',
      _ => 'Esperando operación',
    };
  }

  String _operationWaitMessage() {
    return switch (_selectedOp) {
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
    final payloadType = payload['type'];
    final playerId = payload['targetPlayerId'];
    AppAuditLogger.instance.event('BANK_OP', 'send_to_player',
        data: {'type': payloadType, 'playerId': playerId});
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

    if (!_hasBleContact(transport)) {
      final rssi =
          _closestBleRssi(transport) ?? transport.contactRssiNotifier.value;
      AppAuditLogger.instance.event('BANK_OP', 'no_ble_contact',
          data: {'rssi': rssi, 'contactReady': transport.contactReadyNotifier.value});
      throw TransportUnavailableException(
        rssi == null
            ? 'No se recibió señal de proximidad BLE. Acerca los dispositivos y mantenlos juntos.'
            : 'Jugador fuera de contacto BLE ($rssi dBm). Acerca los dispositivos.',
      );
    }

    final bankTxId = payload['bankTxId'] as String?;
    final requiresConfirmation =
        (payload['type'] == 'bank_state' || payload['type'] == 'handshake') &&
            bankTxId != null;
    if (!requiresConfirmation) {
      await P2PService().sendPayload(payload);
      return;
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingDeliveryAcks[bankTxId] = completer;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        await P2PService().sendPayload(payload);
        try {
          final confirmation =
              await completer.future.timeout(const Duration(seconds: 6));
          final expectedPlayer = payload['targetPlayerId'] as String?;
          final confirmedPlayer = confirmation['playerId'] as String?;
          final expectedBalance = (payload['balance'] as num?)?.toDouble();
          final confirmedBalance =
              (confirmation['appliedBalance'] as num?)?.toDouble();
          final playerMatches = expectedPlayer == null ||
              (confirmedPlayer != null && confirmedPlayer == expectedPlayer);
          final balanceMatches = expectedBalance == null ||
              (confirmedBalance != null &&
                  (confirmedBalance - expectedBalance).abs() < 0.001);
          if (!playerMatches || !balanceMatches) {
            AppAuditLogger.instance.event('BANK_OP', 'confirmation_mismatch',
                data: {'expectedPlayer': expectedPlayer, 'confirmedPlayer': confirmedPlayer});
            throw TransportUnavailableException(
              'El jugador respondió, pero no confirmó el saldo esperado. La operación no se marcará como completada.',
            );
          }
          AppAuditLogger.instance.event('BANK_OP', 'send_confirmed',
              data: {'playerId': confirmedPlayer, 'balance': confirmedBalance});
          return;
        } on TimeoutException {
          if (attempt == 1) rethrow;
        }
      }
    } on TimeoutException {
      throw TransportUnavailableException(
        'El jugador no confirmó que recibió y mostró la operación. Verifica su pantalla y vuelve a intentarlo.',
      );
    } finally {
      _pendingDeliveryAcks.remove(bankTxId);
    }
  }

  void _toast(String msg, Color color) {
    NotificationService().show(msg, backgroundColor: color);
  }

  @override
  Widget build(BuildContext context) {
    final playerColor = context.watch<SessionProvider>().color;

    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kTextSecondary),
          onPressed: () {
            SoundService.playClick();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Panel del Banco',
          style: TextStyle(
              color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: MonopolyBackground(
        child: PlayerColorBackdrop(
        color: playerColor,
        child: SlideTransition(
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
                        const AnimatedEntry(
                          delay: Duration(milliseconds: 150),
                          child: _BleServerPanel(),
                        ),
                        const SizedBox(height: 16),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 180),
                          child: _buildConnectedPlayersList(),
                        ),
                        const SizedBox(height: 24),
                        AnimatedEntry(
                          delay: const Duration(milliseconds: 200),
                          child: _buildOpSelector(),
                        ),
                        const SizedBox(height: 24),
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildOpSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPERACIÓN',
          style:
              TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
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
            Icon(op.icon,
                color: selected ? op.color : kTextSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                op.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? op.color : kTextSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
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
          style:
              TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _amountCtrl,
          onTap: () => SoundService.playClick(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
              color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: const TextStyle(
                color: kGreen, fontSize: 24, fontWeight: FontWeight.w700),
            hintText: '0',
            hintStyle: const TextStyle(color: kBorder, fontSize: 24),
            filled: true,
            fillColor: kBgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
    if (_selectedOp == 'passGo') {
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
              style: const TextStyle(
                  color: kTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black),
                )
              : Icon(op.icon),
          label: Text(
            _sending ? 'Enviando...' : op.label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: op.color,
            foregroundColor:
                op.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedPlayersList() {
    final transport = P2PService().bleTransport;
    return ValueListenableBuilder<bool>(
      valueListenable: transport.serverActiveNotifier,
      builder: (context, active, _) {
        if (!active) return const SizedBox.shrink();
        return ValueListenableBuilder<List<BleConnectedPlayer>>(
          valueListenable: transport.connectedPlayersNotifier,
          builder: (context, players, _) {
            if (players.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBgCard.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.groups_rounded,
                        color: kTextSecondary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Jugadores conectados',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '0',
                      style: TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }
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
                      const Icon(Icons.groups_rounded,
                          color: kGreen, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Jugadores conectados',
                          style: TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${players.length}',
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...players.map((player) => _buildPlayerTile(player)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerTile(BleConnectedPlayer player) {
    final ledger = BankLedgerService();
    final account = ledger.accountFor(player.displayName);
    final quality = player.rssi == null
        ? player.qualityLabel
        : '${player.qualityLabel} - ${player.rssi} dBm';
    final detail =
        '${player.playing ? 'Jugando' : 'Handshake pendiente'} - $quality';
    return GestureDetector(
      onTap: () => _showPlayerDetailDialog(player, account),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: player.qualityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.bluetooth_connected_rounded,
                  color: player.qualityColor, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (player.displayDeviceName.isNotEmpty)
                    Text(
                      player.displayDeviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kTextSecondary.withValues(alpha: 0.62),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  Text(
                    'BLE - $detail',
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
            const SizedBox(width: 8),
            if (account != null)
              Text(
                formatMoney(account.balance),
                style: TextStyle(
                  color: account.bankrupt ? kRed : kGreen,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: player.qualityColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlayerDetailDialog(
    BleConnectedPlayer player,
    BankPlayerAccount? account,
  ) {
    final ledger = BankLedgerService();
    final transactions = ledger.transactionHistory
        .where((tx) => tx['playerId'] == player.displayName)
        .toList();
    final volume = transactions.fold<double>(
      0,
      (sum, tx) => sum + (((tx['amount'] as num?)?.toDouble() ?? 0).abs()),
    );
    final passGoCount =
        transactions.where((tx) => tx['type'] == 'passGo').length;
    final txCount = transactions.length;
    final balance = account?.balance ?? 0;
                final playerColor = _playerColor(player.colorId);
                final avatar = player.avatarId.isNotEmpty
                    ? player.avatarId
                    : '👤';
                final tier = _playerTier(balance);
                final tierLabel = _tierLabel(tier);
                final tierColor = _tierColor(tier);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: DefaultTabController(
          length: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: playerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            avatar,
                            style: TextStyle(
                              fontSize: 20,
                              color: playerColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    labelColor: kGold,
                    unselectedLabelColor: kTextSecondary,
                    indicatorColor: kGold,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    tabs: const [
                      Tab(text: 'Datos Jugador'),
                      Tab(text: 'Datos Conexion'),
                    ],
                  ),
                  Flexible(
                    child: TabBarView(
                      children: [
                        PlayerInfoView(
                          player: player,
                          balance: balance,
                          volume: volume,
                          passGoCount: passGoCount,
                          txCount: txCount,
                          tier: tier,
                          tierLabel: tierLabel,
                          tierColor: tierColor,
                          transactions: transactions,
                        ),

                        _buildConnectionInfoTab(player),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerInfoTab({
    required BleConnectedPlayer player,
    required double balance,
    required double volume,
    required int passGoCount,
    required int txCount,
    required String tier,
    required String tierLabel,
    required Color tierColor,
    BankPlayerAccount? account,
    List<Map<String, dynamic>> transactions = const [],
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Tarjeta del Jugador'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColor.withValues(alpha: 0.18),
                  tierColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: tierColor.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _playerColor(player.colorId)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _playerColor(player.colorId)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      player.avatarId.isNotEmpty
                          ? player.avatarId
                          : '👤',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tierLabel,
                        style: TextStyle(
                          color: tierColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Nivel ${_tierLevel(tier)}',
                        style: TextStyle(
                          color: tierColor.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildSectionHeader('Resumen'),
          _detailRow('Nombre', player.displayName),
          _detailRow('Dispositivo', player.displayDeviceName),
          _detailRow('Conexi\u00f3n', 'Bluetooth (BLE)'),
          const SizedBox(height: 12),
          _buildSectionHeader('Finanzas'),
          _detailRow('Saldo', formatMoney(balance)),
          _detailRow('Volumen total',
              formatMoney(volume)),
          _detailRow(
              'Pases por GO', '$passGoCount'),
          _detailRow('Transacciones',
              '$txCount realizadas'),
          if (account != null && account.investedAmount > 0) ...[
            const SizedBox(height: 12),
            _buildSectionHeader('Inversi\u00f3n Activa'),
            _detailRow('Invertido',
                formatMoney(account.investedAmount)),
            _detailRow('Generado',
                formatMoney(account.generatedAmount)),
            _detailRow('Progreso',
                '${account.currentPasses} / ${account.targetPasses} pases'),
          ],
          if (account != null && account.bankrupt) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: kRed.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gavel_rounded, color: kRed, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Jugador en Bancarrota',
                      style: TextStyle(
                        color: kRed,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (transactions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionHeader(
                '\u00daltimas Transacciones (${transactions.length})'),
            ...transactions.take(5).map((tx) {
              final type = tx['type'] as String? ?? '';
              final amount =
                  (tx['amount'] as num?)?.toDouble() ?? 0;
              final timestamp = tx['timestamp'] as String? ?? '';
              final time = timestamp.length >= 16
                  ? timestamp.substring(11, 16)
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_txIcon(type), size: 14,
                        color: _txColor(type)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _txLabel(type),
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Text(
                      '\$${amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: _txColor(type),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      time,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectionInfoTab(BleConnectedPlayer player) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Dispositivo'),
          _detailRow('Nombre',
              player.name.isNotEmpty ? player.name : '-'),
          _detailRow(
              'Dispositivo', player.displayDeviceName),
          _detailRow('ID BLE', player.id),
          _detailRow(
              'ID Instalaci\u00f3n',
              player.deviceInstallationId.isNotEmpty
                  ? player.deviceInstallationId
                  : '-'),
          const SizedBox(height: 12),
          _buildSectionHeader('Estado Conexi\u00f3n'),
          _detailRow('Handshake',
              player.playing ? 'Completado' : 'Pendiente'),
          _detailRow('Suscripci\u00f3n GATT',
              player.subscribed ? 'Activa' : 'Inactiva'),
          const SizedBox(height: 12),
          _detailRow(
              '\u00daltima actividad',
              '${player.lastSeen.hour.toString().padLeft(2, '0')}:'
                  '${player.lastSeen.minute.toString().padLeft(2, '0')}:'
                  '${player.lastSeen.second.toString().padLeft(2, '0')}'),
        ],
      ),
    );
  }

  String _playerTier(double balance) {
    if (balance >= 15000) return 'black';
    if (balance >= 8000) return 'platinum';
    if (balance >= 4000) return 'gold';
    return 'standard';
  }

  String _tierLabel(String tier) {
    return switch (tier) {
      'black' => 'ULTIMATE BLACK',
      'platinum' => 'PLATINUM PRESTIGE',
      'gold' => 'GOLD MEMBERSHIP',
      _ => 'CLASSIC EDITION',
    };
  }

  int _tierLevel(String tier) {
    return switch (tier) {
      'standard' => 1,
      'gold' => 2,
      'platinum' => 3,
      'black' => 4,
      _ => 1,
    };
  }

  Color _tierColor(String tier) {
    return switch (tier) {
      'standard' => const Color(0xFF90A4AE),
      'gold' => const Color(0xFFFFD700),
      'platinum' => const Color(0xFF1E88E5),
      'black' => const Color(0xFF424242),
      _ => const Color(0xFF90A4AE),
    };
  }

  Color _playerColor(String colorId) {
    const colors = [
      Color(0xFFE53935),
      Color(0xFF8E24AA),
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFFDD835),
      Color(0xFFFF7043),
      Color(0xFF00ACC1),
      Color(0xFFECEFF1),
    ];
    final index = int.tryParse(colorId) ?? 0;
    if (index >= 0 && index < colors.length) return colors[index];
    return colors[0];
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: kGold,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _txLabel(String type) {
    return switch (type) {
      'payment' => 'Pago del banco',
      'charge' => 'Cobro del banco',
      'passGo' => 'Pas\u00f3 por GO',
      'handshake_initial' => 'Handshake inicial',
      'handshake_reconnect' => 'Reconexi\u00f3n',
      'bankruptcy' => 'Bancarrota',
      'investment_opened' => 'Inversi\u00f3n abierta',
      'investment_completed' => 'Inversi\u00f3n completada',
      'investment_early_withdrawal' => 'Retiro anticipado',
      _ => type,
    };
  }

  IconData _txIcon(String type) {
    return switch (type) {
      'payment' => Icons.arrow_downward_rounded,
      'charge' => Icons.arrow_upward_rounded,
      'passGo' => Icons.flag_rounded,
      'handshake_initial' => Icons.handshake_rounded,
      'handshake_reconnect' => Icons.handshake_rounded,
      'bankruptcy' => Icons.gavel_rounded,
      'investment_opened' => Icons.trending_up_rounded,
      'investment_completed' => Icons.trending_up_rounded,
      'investment_early_withdrawal' => Icons.trending_up_rounded,
      _ => Icons.swap_horiz_rounded,
    };
  }

  Color _txColor(String type) {
    return switch (type) {
      'payment' || 'passGo' => kGreen,
      'charge' || 'bankruptcy' => kRed,
      _ => kGold,
    };
  }
}

class _BankOperationDialogController {
  _BankOperationDialogController({required this.transportType})
      : title = ValueNotifier<String>('Preparando operación'),
        message = ValueNotifier<String>('Esperando contacto BLE...');

  final TransportType transportType;
  final ValueNotifier<String> title;
  final ValueNotifier<String> message;
  final completed = ValueNotifier<bool>(false);
  final failed = ValueNotifier<bool>(false);
  final cancelled = ValueNotifier<bool>(false);
  IconData failedIcon = Icons.close_rounded;
  Color failedColor = kRed;

  void update({
    required String title,
    required String message,
  }) {
    if (completed.value || failed.value || cancelled.value) return;
    this.title.value = title;
    this.message.value = message;
  }

  void complete(String message) {
    completed.value = true;
    failed.value = false;
    title.value = 'Proceso completado';
    this.message.value = message;
  }

  void fail({
    required String title,
    required String message,
    IconData icon = Icons.close_rounded,
    Color color = kRed,
  }) {
    failedIcon = icon;
    failedColor = color;
    failed.value = true;
    completed.value = false;
    this.title.value = title;
    this.message.value = message;
  }
}

class _OperationLoadingVisual extends StatefulWidget {
  const _OperationLoadingVisual({
    required this.completed,
    required this.failed,
    required this.transportType,
    required this.failedIcon,
    required this.failedColor,
  });

  final bool completed;
  final bool failed;
  final TransportType transportType;
  final IconData failedIcon;
  final Color failedColor;

  @override
  State<_OperationLoadingVisual> createState() =>
      _OperationLoadingVisualState();
}

class _OperationLoadingVisualState extends State<_OperationLoadingVisual>
    with SingleTickerProviderStateMixin {
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
    final waitingColor = Colors.blue;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      child: widget.failed
          ? Container(
              key: const ValueKey('failed'),
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.failedColor.withValues(alpha: 0.14),
                border: Border.all(
                  color: widget.failedColor.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.failedColor.withValues(alpha: 0.24),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                widget.failedIcon,
                color: widget.failedColor,
                size: 64,
              ),
            )
          : widget.completed
              ? Container(
                  key: const ValueKey('completed'),
                  width: 136,
                  height: 136,
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
                    size: 64,
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
                          _PulseRing(
                            progress: pulse,
                            delay: 0,
                            color: waitingColor,
                          ),
                          _PulseRing(
                            progress: pulse,
                            delay: 0.33,
                            color: waitingColor,
                          ),
                          _PulseRing(
                            progress: pulse,
                            delay: 0.66,
                            color: waitingColor,
                          ),
                          Positioned(
                            left: 14,
                            child: Icon(
                              Icons.account_balance_rounded,
                              color: kGold,
                              size: 48,
                            ),
                          ),
                          Positioned(
                            right: 8 + (30 * pulse),
                            child: Transform.rotate(
                              angle: -0.10 * math.sin(pulse * math.pi),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: kBgCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: waitingColor,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          waitingColor.withValues(alpha: 0.3),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.smartphone_rounded,
                                  color: waitingColor,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: waitingColor.withValues(alpha: 0.25),
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
  const _PulseRing({
    required this.progress,
    required this.delay,
    required this.color,
  });

  final double progress;
  final double delay;
  final Color color;

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
          color: color.withValues(alpha: opacity),
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
            child: const Icon(Icons.account_balance_rounded,
                color: kGold, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Banca Central',
                  style: TextStyle(
                      color: kGold, fontWeight: FontWeight.w800, fontSize: 16),
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

  Future<bool> _ensureBleReady(
      BuildContext context, BleTransport transport) async {
    var status = await transport.refreshAvailability();
    if (status == BleAvailabilityStatus.ready) return true;
    if (!context.mounted) return false;

    if (status == BleAvailabilityStatus.noHardware) {
      _showMessage(
          context, 'Este dispositivo no tiene Bluetooth LE disponible.');
      return false;
    }

    if (status == BleAvailabilityStatus.missingPermissions) {
      final allow = await _confirm(
        context,
        title: 'Permisos de Bluetooth',
        message:
            'Para activar el servidor BLE del banco necesito permisos de Bluetooth. ¿Quieres permitirlos ahora?',
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
        _showMessage(context,
            'Permisos de Bluetooth pendientes. Revisa los permisos de la app e intenta de nuevo.');
      }
      return false;
    }

    if (status == BleAvailabilityStatus.bluetoothOff) {
      return _askToOpenBleSettings(context, transport);
    }

    _showMessage(context,
        'No pude verificar Bluetooth. Revisa los ajustes e intenta de nuevo.');
    return false;
  }

  Future<bool> _askToOpenBleSettings(
      BuildContext context, BleTransport transport) async {
    final open = await _confirm(
      context,
      title: 'Bluetooth apagado',
      message:
          'Para usar el banco por BLE debes activar Bluetooth. ¿Quieres abrir los ajustes?',
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
                final subtitle = (active && status.isNotEmpty)
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
                            connected
                                ? Icons.bluetooth_connected_rounded
                                : Icons.bluetooth_rounded,
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
                                onPressed: () async {
                                  SoundService.playClick();
                                  await transport.stopServer();
                                },
                                icon: const Icon(Icons.stop_circle_outlined,
                                    size: 16),
                                label: const Text('Detener Servidor BLE'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kRed,
                                  side: const BorderSide(color: kRed),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () async {
                                  SoundService.playClick();
                                  final ready =
                                      await _ensureBleReady(context, transport);
                                  if (!ready || !context.mounted) return;
                                  await P2PService().startBleBankServer();
                                  P2PService().setTransport(TransportType.ble);
                                },
                                icon: const Icon(
                                    Icons.bluetooth_searching_rounded,
                                    size: 16),
                                label: const Text('Iniciar Servidor BLE'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
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
