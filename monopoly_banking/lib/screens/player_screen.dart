import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:money_manager/core/constants.dart';
import 'package:money_manager/core/game_transitions.dart';
import 'package:money_manager/models/transaction_model.dart';
import 'package:money_manager/providers/session_provider.dart';
import 'package:money_manager/providers/stats_provider.dart';
import 'package:money_manager/providers/wallet_controller.dart';
import 'package:money_manager/screens/bankruptcy_screen.dart';
import 'package:money_manager/screens/kicked_screen.dart';
import 'package:money_manager/screens/winner_screen.dart';
import 'package:money_manager/screens/onboarding_screen.dart';
import 'package:money_manager/services/error_translator_service.dart';
import 'package:money_manager/services/bank_ledger_service.dart';
import 'package:money_manager/services/bank_settings_service.dart';
import 'package:money_manager/services/device_identity_service.dart';
import 'package:money_manager/services/notification_service.dart';
import 'package:money_manager/services/p2p_service.dart';
import 'package:money_manager/services/sound_service.dart';
import 'package:money_manager/services/transports/p2p_transport.dart';
import 'package:money_manager/widgets/animated_entry.dart';
import 'package:money_manager/widgets/animated_avatar.dart';
import 'package:money_manager/widgets/premium_dialog.dart';
import 'package:money_manager/widgets/money_manager_background.dart';
import 'package:money_manager/widgets/player_color_backdrop.dart';
import 'package:money_manager/widgets/transaction_tile.dart';
import 'package:money_manager/widgets/transport_selector.dart';
import 'package:money_manager/widgets/app_spinner.dart';
import 'package:money_manager/screens/wallet/balance_card_section.dart';
import 'package:money_manager/screens/wallet/vault_section_widget.dart';
import 'package:money_manager/screens/wallet/ws_connect_button.dart';
import 'package:money_manager/screens/wallet/stat_chip.dart';

part 'player/state_mixin_connection.dart';
part 'player/state_mixin_incoming.dart';
part 'player/state_mixin_builders.dart';
part 'player/state_mixin_dialogs.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, _PlayerConnection, _PlayerIncoming, _PlayerBuilders, _PlayerDialogs {
  late final AnimationController _pulseCtrl;
  late final ConfettiController _confettiCtrl;

  bool _bankruptcyScreenOpen = false;
  bool _hasBeenKicked = false;
  bool _inReconnectionGrace = false;
  Timer? _reconnectionTimer;
  final bool _isExiting = false;
  StreamSubscription<Map<String, dynamic>>? _payloadSub;
  StreamSubscription<TxType>? _txSub;
  StreamSubscription<CardTier>? _tierSub;
  Timer? _tierCelebrationTimer;
  CardTier? _pendingCelebrationTier;
  bool _evolutionDialogOpen = false;
  bool _wsScanning = false;
  bool _userRequestedWsDisconnect = false;
  bool _reconnecting = false;
  bool _dialogActive = false;
  VoidCallback? _wsClientConnectionListener;
  ValueNotifier<bool>? _bankruptNotifierRef;
  final Set<String> _seenTxIds = <String>{};
  final List<String> _seenTxIdOrder = <String>[];

  Color? _lastColor;
  String? _lastName;
  String? _lastAvatarId;
  double? _lastBalance;
  final List<double> _lastHistory = [];
  String? _walletFilterType;
  String _walletSortBy = 'date';
  bool _walletSortAscending = false;

  Completer<void>? _pendingBankOperationCompleter;
  String? _pendingBankOperationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));

    _listenForIncoming();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await P2PService().initTransports(isBank: false);
      await P2PService().startReceiving(null);
      _listenToBankruptcy();
      _listenToTierEvolution();
      _listenForWsDisconnection();
      _startWsClient();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_userRequestedWsDisconnect) {
      final connected = P2PService().wsTransport.clientConnectedNotifier.value;
      if (!connected && _wsBankIp != null && !_wsConnecting) {
        _reconnectionTimer?.cancel();
        _reconnectionTimer = null;
        _inReconnectionGrace = false;
        _reconnecting = true;
        _connectToWsBank(_wsBankIp!, _wsBankPort);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsScanning = false;
    _wsConnecting = false;
    P2PService().wsTransport.stop();
    _payloadSub?.cancel();
    _txSub?.cancel();
    _tierSub?.cancel();
    _tierCelebrationTimer?.cancel();
    final bankruptListener = _bankruptListener;
    if (bankruptListener != null && _bankruptNotifierRef != null) {
      _bankruptNotifierRef!.removeListener(bankruptListener);
    }
    final wsClientConnectionListener = _wsClientConnectionListener;
    if (wsClientConnectionListener != null) {
      P2PService().wsTransport.clientConnectedNotifier.removeListener(
            wsClientConnectionListener,
          );
    }
    _reconnectionTimer?.cancel();
    _pulseCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }
}

