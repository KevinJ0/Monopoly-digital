import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/core/game_transitions.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bankruptcy_screen.dart';
import 'package:monopoly_banking/screens/kicked_screen.dart';
import 'package:monopoly_banking/screens/onboarding_screen.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/services/device_identity_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/animated_avatar.dart';
import 'package:monopoly_banking/widgets/premium_dialog.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:monopoly_banking/widgets/transport_selector.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';
import 'package:monopoly_banking/screens/wallet/balance_card_section.dart';
import 'package:monopoly_banking/screens/wallet/vault_section_widget.dart';
import 'package:monopoly_banking/screens/wallet/ws_connect_button.dart';
import 'package:monopoly_banking/screens/wallet/stat_chip.dart';

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
  late final AnimationController _welcomeCtrl;
  late final Animation<double> _welcomeScale;
  late final Animation<double> _welcomeOpacity;
  late final ConfettiController _confettiCtrl;

  bool _showWelcome = false;
  bool _bankruptcyScreenOpen = false;
  bool _hasBeenKicked = false;
  bool _inReconnectionGrace = false;
  Timer? _reconnectionTimer;
  bool _isExiting = false;
  StreamSubscription<Map<String, dynamic>>? _payloadSub;
  StreamSubscription<TxType>? _txSub;
  StreamSubscription<CardTier>? _tierSub;
  Timer? _tierCelebrationTimer;
  CardTier? _pendingCelebrationTier;
  bool _evolutionDialogOpen = false;
  bool _wsScanning = false;
  bool _userRequestedWsDisconnect = false;
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
    debugPrint('[PLAYER] INIT_STATE');
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
      await P2PService().initTransports(isBank: false);
      await P2PService().startReceiving(null);
      _listenToBankruptcy();
      _listenToTierEvolution();
      _listenForWsDisconnection();
      _startWsClient();
    });
  }

  @override
  void dispose() {
    debugPrint('[PLAYER] DISPOSE isExiting=$_isExiting');
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
    _welcomeCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }
}
