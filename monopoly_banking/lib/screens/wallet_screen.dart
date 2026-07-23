import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/core/game_transitions.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bankruptcy_screen.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/device_identity_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/foreground_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/services/transports/ws_models.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/animated_avatar.dart';
import 'package:monopoly_banking/widgets/premium_dialog.dart';
import 'package:monopoly_banking/widgets/player_info_widget.dart';
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:monopoly_banking/widgets/transport_selector.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';

import 'wallet/stat_chip.dart';
import 'wallet/ws_bank_panel.dart';
import 'wallet/connection_panel.dart';

part 'wallet/state_mixin_connection.dart';
part 'wallet/state_mixin_incoming.dart';
part 'wallet/state_mixin_builders.dart';
part 'wallet/state_mixin_dialogs.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, AutomaticKeepAliveClientMixin, _WalletConnection, _WalletIncoming, _WalletBuilders, _WalletDialogs {
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateKeepAlive();
  }
  late final AnimationController _pulseCtrl;
  late final AnimationController _welcomeCtrl;
  late final Animation<double> _welcomeScale;
  late final Animation<double> _welcomeOpacity;
  late final ConfettiController _confettiCtrl;

  bool _showWelcome = false;
  bool _bankruptcyScreenOpen = false;
  bool _isExiting = false;
  StreamSubscription<Map<String, dynamic>>? _payloadSub;
  StreamSubscription<TxType>? _txSub;
  bool _dialogActive = false;
  bool _bankTransferHoldDialogOpen = false;
  ValueNotifier<bool>? _bankruptNotifierRef;
  final Map<String, Completer<Map<String, dynamic>>> _bankDeliveryAcks = {};
  VoidCallback? _bankruptListener;
  VoidCallback? _bankStatsListener;

  Color? _lastColor;
  String? _lastName;
  String? _lastAvatarId;
  double? _lastBalance;

  VoidCallback? _wsConnectionsListener;
  VoidCallback? _bankServerListener;
  final Set<String> _announcedWsConnections = {};

  String? _walletFilterType;
  String _walletSortBy = 'date';
  bool _walletSortAscending = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[┊] WALLET_INIT_STATE (bank mode)');
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _welcomeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _welcomeScale =
        CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeOutBack);
    _welcomeOpacity =
        CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeIn);

    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));

    _listenForIncoming();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<SessionProvider>();
      _listenToBankStats();
      await P2PService().initTransports(isBank: true);
      _listenToBankruptcy();
      _connectToHost(session);
      _listenForBankPlayerConnections();
      _listenForBankServerState();
    });
  }

  @override
  void dispose() {
    debugPrint('[┊] WALLET_DISPOSE isExiting=$_isExiting');
    for (final completer in _bankDeliveryAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Pantalla cerrada'));
      }
    }
    _bankDeliveryAcks.clear();
    WidgetsBinding.instance.removeObserver(this);
    P2PService().wsTransport.stop();
    _payloadSub?.cancel();
    _txSub?.cancel();
    final bankruptListener = _bankruptListener;
    if (bankruptListener != null && _bankruptNotifierRef != null) {
      _bankruptNotifierRef!.removeListener(bankruptListener);
    }
    final bankStatsListener = _bankStatsListener;
    if (bankStatsListener != null) {
      BankLedgerService().statsRevision.removeListener(bankStatsListener);
    }
    final wsConnectionsListener = _wsConnectionsListener;
    if (wsConnectionsListener != null) {
      P2PService().wsTransport.connectedPlayersNotifier.removeListener(
            wsConnectionsListener,
          );
    }
    final bankServerListener = _bankServerListener;
    if (bankServerListener != null) {
      P2PService()
          .wsTransport
          .serverActiveNotifier
          .removeListener(bankServerListener);
    }
    _announcedWsConnections.clear();
    _pulseCtrl.dispose();
    _welcomeCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }
}
