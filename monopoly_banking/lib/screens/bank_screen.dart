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
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/ws_models.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/app_audit_logger.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/core/game_transitions.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/widgets/player_info_widget.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';
import 'package:monopoly_banking/screens/bank/bank_settings_screen.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/foreground_service.dart';

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
    with TickerProviderStateMixin, WidgetsBindingObserver, AutomaticKeepAliveClientMixin, _BankConnection, _BankBuilders, _BankDialogs {
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateKeepAlive();
  }
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
  String? _historyFilterType;
  bool _historySortAscending = false;
  String _historySortBy = 'date';

  List<_OpOption> get _operations {
    final settings = BankSettingsService();
    final built = <_OpOption>[
      const _OpOption(
          id: 'payment',
          label: 'Cobrar al jugador',
          icon: Icons.arrow_upward_rounded,
          color: kRed),
      const _OpOption(
          id: 'receive',
          label: 'Pagar al jugador',
          icon: Icons.arrow_downward_rounded,
          color: kGreen),
      _OpOption(
          id: 'passGo',
          label: 'Pasar por GO (\$${settings.passGoAmount.round()})',
          icon: Icons.flag_rounded,
          color: kGold),
      for (final c in settings.customOps)
        _OpOption(
          id: 'custom:${c.id}',
          label: c.name,
          icon: BankSettingsService.availableIcons[c.iconKey] ??
              Icons.payments_rounded,
          color: c.isGive ? kGreen : kRed,
        ),
    ];
    return built;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BankSettingsService().load();
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
        return;
      }
      if (payload['type'] == 'handshake_confirm' ||
          payload['type'] == 'ws_identity') {
        final name = payload['name'] as String? ?? 'Jugador';
        if (payload['type'] == 'ws_identity') {
          final account = BankLedgerService().accountFor(name);
          final installationId =
              (payload['deviceInstallationId'] as String?) ?? '';
          if (account != null &&
              (account.bankrupt ||
                  BankLedgerService().isDeviceBanned(installationId))) {
            return;
          }

          final isReturningPlayer = account != null &&
              account.deviceInstallationId.isNotEmpty &&
              account.deviceInstallationId == installationId;

          NotificationService().show(
            isReturningPlayer
                ? '$name se reconectó a la partida'
                : '$name se conectó al banco',
            backgroundColor: kGreen,
            duration: const Duration(seconds: 4),
            dedupeKey: 'ws-connected:$name',
          );
        }
        _connectedPlayerName = name;
      }
    }, onError: (e, s) {
      if (mounted) context.showFriendlyError(e, s);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await P2PService().initTransports(isBank: true);
        await P2PService().startWsServer();
        await BankForegroundService().start();
      } catch (e, s) {
        if (mounted) context.showFriendlyError(e, s);
      }
    });
  }

  bool _isFixedOpGive() {
    if (_selectedOp == 'passGo') return true;
    if (_selectedOp.startsWith('custom:')) {
      final customId = _selectedOp.substring('custom:'.length);
      final match = BankSettingsService()
          .customOps
          .where((c) => c.id == customId)
          .firstOrNull;
      return match?.isGive ?? true;
    }
    return _selectedOp == 'receive';
  }

  double _fixedAmountForSelectedOp() {
    if (_selectedOp == 'passGo') {
      return BankSettingsService().passGoAmount;
    }
    if (_selectedOp.startsWith('custom:')) {
      final customId = _selectedOp.substring('custom:'.length);
      final match = BankSettingsService()
          .customOps
          .where((c) => c.id == customId)
          .firstOrNull;
      return match?.amount ?? 0;
    }
    return 0;
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<dynamic>(
      GameFadeRoute(page: BankSettingsScreen()),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(P2PService().startWsServer());
      unawaited(BankForegroundService().start());
    }
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
    BankForegroundService().stop();
    super.dispose();
  }
}
