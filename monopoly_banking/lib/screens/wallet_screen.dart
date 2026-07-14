import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/core/game_transitions.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bankruptcy_screen.dart';
import 'package:monopoly_banking/screens/ble_test_screen.dart';
import 'package:monopoly_banking/services/error_translator_service.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/device_identity_service.dart';
import 'package:monopoly_banking/services/network_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/transports/ble_transport.dart';
import 'package:monopoly_banking/services/transports/p2p_transport.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';
import 'package:monopoly_banking/widgets/animated_avatar.dart';
import 'package:monopoly_banking/widgets/odometer_widget.dart';
import 'package:monopoly_banking/widgets/premium_dialog.dart';
import 'package:monopoly_banking/widgets/monopoly_background.dart';
import 'package:monopoly_banking/widgets/player_color_backdrop.dart';
import 'package:monopoly_banking/widgets/player_info_widget.dart';
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:monopoly_banking/widgets/transport_selector.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';

part 'wallet/premium_card.dart';
part 'wallet/card_styles.dart';
part 'wallet/stat_chip.dart';
part 'wallet/connected_player_tile.dart';
part 'wallet/carbon_fiber_painter.dart';
part 'wallet/shimmer_card.dart';
part 'wallet/balance_card_section.dart';
part 'wallet/vault_section_widget.dart';
part 'wallet/ble_bank_panel.dart';
part 'wallet/ble_client_panel.dart';
part 'wallet/discovered_banks_list.dart';
part 'wallet/connection_panel.dart';
part 'wallet/ble_connect_button.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver, _WalletConnection, _WalletIncoming, _WalletBuilders, _WalletDialogs {
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
  StreamSubscription<CardTier>? _tierSub;
  Timer? _tierCelebrationTimer;
  CardTier? _pendingCelebrationTier;
  bool _evolutionDialogOpen = false;
  bool _bleScanning = false;
  bool _userRequestedBleDisconnect = false;
  bool _dialogActive = false;
  VoidCallback? _bleClientConnectionListener;
  bool _wasBleClientConnected = false;
  bool _bankTransferHoldDialogOpen = false;
  ValueNotifier<bool>? _bankruptNotifierRef;
  final Set<String> _seenTxIds = <String>{};
  final List<String> _seenTxIdOrder = <String>[];
  final Map<String, Completer<Map<String, dynamic>>> _bankDeliveryAcks = {};
  VoidCallback? _bankruptListener;
  VoidCallback? _bankStatsListener;

  String? _lastRole;
  Color? _lastColor;
  String? _lastName;
  String? _lastAvatarId;
  int? _lastColorId;
  double? _lastBalance;
  final List<double> _lastHistory = [];

  late final VoidCallback _typeListener;
  VoidCallback? _bleConnectionsListener;
  VoidCallback? _bankServerListener;
  final Set<String> _announcedBleConnections = {};
  Completer<void>? _pendingBankOperationCompleter;
  String? _pendingBankOperationId;
  Completer<void>? _pendingTransferCompleter;

  @override
  void initState() {
    super.initState();
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

    _typeListener = () {
      if (P2PService().currentType != TransportType.ble) {
        final bleConnected =
            P2PService().bleTransport.clientConnectedNotifier.value;
        if (_bleScanning || bleConnected) _stopBleClient();
      }
    };
    P2PService().typeNotifier.addListener(_typeListener);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<SessionProvider>();
      if (session.isBank) {
        _listenToBankStats();
      }
      await P2PService().initTransports(isBank: session.isBank);
      _listenToBankruptcy();
      _listenToTierEvolution();
      _connectToHost(session);
      if (session.isBank) {
        _listenForBankPlayerConnections();
        _listenForBankServerState();
      } else {
        _listenForBleBankDisconnection();
        _startBleClient();
      }
    });
  }

  @override
  void dispose() {
    for (final completer in _bankDeliveryAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Pantalla cerrada'));
      }
    }
    _bankDeliveryAcks.clear();
    WidgetsBinding.instance.removeObserver(this);
    _stopBleClient();
    _payloadSub?.cancel();
    _txSub?.cancel();
    _tierSub?.cancel();
    _tierCelebrationTimer?.cancel();
    final bankruptListener = _bankruptListener;
    if (bankruptListener != null && _bankruptNotifierRef != null) {
      _bankruptNotifierRef!.removeListener(bankruptListener);
    }
    final bankStatsListener = _bankStatsListener;
    if (bankStatsListener != null) {
      BankLedgerService().statsRevision.removeListener(bankStatsListener);
    }
    P2PService().typeNotifier.removeListener(_typeListener);
    final bleConnectionsListener = _bleConnectionsListener;
    if (bleConnectionsListener != null) {
      P2PService().bleTransport.connectedPlayersNotifier.removeListener(
            bleConnectionsListener,
          );
    }
    final bleClientConnectionListener = _bleClientConnectionListener;
    if (bleClientConnectionListener != null) {
      P2PService().bleTransport.clientConnectedNotifier.removeListener(
            bleClientConnectionListener,
          );
    }
    final bankServerListener = _bankServerListener;
    if (bankServerListener != null) {
      P2PService()
          .bleTransport
          .serverActiveNotifier
          .removeListener(bankServerListener);
    }
    _announcedBleConnections.clear();
    _pulseCtrl.dispose();
    _welcomeCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }
}


