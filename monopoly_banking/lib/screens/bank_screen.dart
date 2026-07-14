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
import 'package:monopoly_banking/widgets/app_spinner.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';

part 'bank/operation_dialog_controller.dart';
part 'bank/operation_loading_visual.dart';
part 'bank/pulse_ring.dart';
part 'bank/bank_header.dart';
part 'bank/op_option.dart';
part 'bank/state_mixin_connection.dart';
part 'bank/state_mixin_builders.dart';
part 'bank/state_mixin_dialogs.dart';

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, _BankConnection, _BankBuilders, _BankDialogs {
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
  String? _historyFilterPlayer;
  bool _historySortAscending = false;

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
    BankLedgerService().initHeldTransfersCount();
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
}
