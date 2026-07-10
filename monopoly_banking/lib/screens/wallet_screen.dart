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
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/bank_screen.dart';
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
import 'package:monopoly_banking/widgets/transaction_tile.dart';
import 'package:monopoly_banking/widgets/transport_selector.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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
      }
    });
  }

  void _connectToHost(SessionProvider session) {
    // WiFi no participa como medio de juego. Los jugadores se conectan por
    // BLE/NFC para evitar operaciones fuera de contacto.
  }

  void _listenForBankServerState() {
    _bankServerListener ??= () {
      if (mounted && !_dialogActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    };
    P2PService().bleTransport.serverActiveNotifier
        .addListener(_bankServerListener!);
  }

  void _listenForBankPlayerConnections() {
    final notifier = P2PService().bleTransport.connectedPlayersNotifier;
    _bleConnectionsListener ??= () {
      final connected = notifier.value
          .where((player) => player.subscribed)
          .toList(growable: false);
      final connectedIds = connected.map((player) => player.id).toSet();
      _announcedBleConnections.removeWhere(
        (deviceId) => !connectedIds.contains(deviceId),
      );

      for (final player in connected) {
        if (_announcedBleConnections.contains(player.id)) {
          continue;
        }
        _announcedBleConnections.add(player.id);
        debugPrint(
          '[BLE bank] Jugador suscrito id=${player.id} nombre=${player.displayName}',
        );
        NotificationService().show(
          '${player.displayName} se conectó al banco\n'
          'Dispositivo: ${player.displayDeviceName}',
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          dedupeKey: 'ble-connected:${player.id}',
        );
      }
    };
    notifier.addListener(_bleConnectionsListener!);
    _bleConnectionsListener!();
  }

  void _listenForBleBankDisconnection() {
    final notifier = P2PService().bleTransport.clientConnectedNotifier;
    _wasBleClientConnected = notifier.value;
    _bleClientConnectionListener ??= () {
      final connected = notifier.value;

      if (connected && _bleScanning) {
        _bleScanning = false;
        if (mounted && !_dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      } else if (!connected &&
          _wasBleClientConnected &&
          !_userRequestedBleDisconnect) {
        _bleScanning = true;
        if (mounted && !_dialogActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      }

      if (_wasBleClientConnected &&
          !connected &&
          !_userRequestedBleDisconnect &&
          mounted) {
        Future.microtask(() {
          if (!mounted || _userRequestedBleDisconnect || _bleScanning) return;
          NotificationService().show(
            'Se perdi\u00f3 la conexi\u00f3n con el banco. El servidor BLE fue apagado o dej\u00f3 de estar disponible.',
            backgroundColor: kRed,
            duration: const Duration(seconds: 5),
            dedupeKey: 'ble-bank-disconnected',
          );
        });
      }
      _wasBleClientConnected = connected;
    };
    notifier.addListener(_bleClientConnectionListener!);
  }

  void _listenToBankStats() {
    final revision = BankLedgerService().statsRevision;
    _bankStatsListener ??= () {
      if (!mounted) return;
      final session = HiveService.sessionBox.get('current');
      if (session == null || session.role != 'banco') return;
      context.read<StatsProvider>().restore(
            volume: session.totalVolume,
            count: session.txCount,
            passGo: session.passGoCount,
          );
    };
    revision.addListener(_bankStatsListener!);
    _bankStatsListener!();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = context.read<SessionProvider>();
      if (session.isBank) {
        P2PService().bleTransport.refreshAvailability().then((_) {
          if (mounted && !_dialogActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        });
      }
    }
  }

  void _listenForIncoming() {
    final wallet = context.read<WalletController>();
    final session = context.read<SessionProvider>();

    _payloadSub ??= P2PService().payloadStream.listen((payload) async {
      if (!mounted) return;
      final txId = payload['txId'] as String?;
      if (txId != null) {
        if (_seenTxIds.contains(txId)) return;
        _seenTxIds.add(txId);
        _seenTxIdOrder.add(txId);
        if (_seenTxIdOrder.length > 80) {
          final removed = _seenTxIdOrder.removeAt(0);
          _seenTxIds.remove(removed);
        }
      }
      final type = payload['type'] as String?;

      if (!session.isBank && type == 'bank_server_stopping') {
        _userRequestedBleDisconnect = true;
        _bleScanning = false;
        try {
          await P2PService().bleTransport.stopClientScan();
        } finally {
          _userRequestedBleDisconnect = false;
        }
        if (mounted) {
          _safeSetState(() {});
          NotificationService().show(
            'El banco apagó el servidor BLE. Has sido desconectado.',
            backgroundColor: kRed,
            duration: const Duration(seconds: 5),
            dedupeKey: 'ble-bank-disconnected',
          );
        }
        return;
      }

      if (session.isBank && type == 'bank_state_ack') {
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null) {
          final completer = _bankDeliveryAcks[bankTxId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(payload);
          }
        }
        return;
      }

      if (!session.isBank &&
          (type == 'bank_session_status' ||
              type == 'handshake' ||
              type == 'bank_state' ||
              type == 'bank_operation_error' ||
              type == 'bank_access_denied')) {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        final changed = await session.adoptBankSession(
          payload['bankSessionId'] as String?,
        );
        if (changed) {
          _setBleClientIdentity();
          NotificationService().show(
            'El banco terminó la partida anterior. Se inició una nueva partida.',
            backgroundColor: kGold,
            duration: const Duration(seconds: 5),
          );
          if (type != 'handshake') return;
        }
        if (type == 'bank_session_status') return;
      }

      if (session.isBank && type != 'ble_proximity') {
        final deviceInstallationId =
            (payload['deviceInstallationId'] as String?)?.trim();
        if (deviceInstallationId != null &&
            deviceInstallationId.isNotEmpty &&
            BankLedgerService().isDeviceBanned(deviceInstallationId)) {
          final playerId = ((payload['playerId'] as String?) ??
                  (payload['name'] as String?) ??
                  'Jugador')
              .trim();
          await _sendBlockedDeviceState(
            playerId,
            transportType: _transportForIncomingPayload(payload),
          );
          final bleDeviceId = payload['_bleDeviceId'] as String?;
          if (bleDeviceId != null) {
            P2PService().bleTransport.markPlayerInactive(bleDeviceId);
            unawaited(_disconnectBannedBleClient(bleDeviceId));
          }
          return;
        }

        if ((type == 'ble_identity' || type == 'nfc_identity') &&
            deviceInstallationId != null &&
            deviceInstallationId.isNotEmpty) {
          final playerId = ((payload['playerId'] as String?) ??
                  (payload['name'] as String?) ??
                  '')
              .trim();
          final existingAccount = BankLedgerService().accountFor(playerId);
          final nameBelongsToAnotherDevice = playerId.isNotEmpty &&
              existingAccount != null &&
              existingAccount.deviceInstallationId.isNotEmpty &&
              existingAccount.deviceInstallationId != deviceInstallationId;
          if (nameBelongsToAnotherDevice) {
            await _sendBankError(
              playerId,
              'El nombre "$playerId" ya pertenece a otro jugador de esta partida. Elige un nombre diferente.',
              transportType: _transportForIncomingPayload(payload),
            );
            final bleDeviceId = payload['_bleDeviceId'] as String?;
            if (bleDeviceId != null) {
              P2PService().bleTransport.markPlayerInactive(bleDeviceId);
            }
            return;
          }
          final isReturningPlayer = existingAccount != null &&
              !existingAccount.bankrupt &&
              existingAccount.deviceInstallationId == deviceInstallationId;
          final playerNeedsHandshake =
              (payload['isHandshakeDone'] as bool?) != true;
          final bleDeviceId = payload['_bleDeviceId'] as String?;
          if (type != 'nfc_identity' &&
              isReturningPlayer &&
              bleDeviceId != null) {
            P2PService().bleTransport.markPlayerActive(bleDeviceId);
          }
          if (isReturningPlayer && playerNeedsHandshake) {
            final restorePayload = <String, dynamic>{
              'type': 'handshake',
              'targetPlayerId': playerId,
              'avatarId': session.avatarId,
              'colorId': session.colorId,
              'gameId': 'monopoly',
              'name': session.name,
              'eventType': 'handshake_restore',
              'amount': 0,
              'bankSessionId': BankLedgerService().currentBankSessionId,
              ...existingAccount.toClientState(),
            };
            final sourceTransport = _transportForIncomingPayload(payload);
            P2PService().setTransport(sourceTransport);
            try {
              await P2PService().sendPayload(restorePayload);
            } on TransportUnavailableException {
              // La identidad se reenvía cuando el canal BLE termina de
              // suscribirse; ese segundo intento restaurará la sesión.
            }
          } else if (isReturningPlayer) {
            final syncResult = BankLedgerResult(
              account: existingAccount,
              transactionId: 'sync-${DateTime.now().microsecondsSinceEpoch}',
              eventType: 'bank_sync',
              amount: 0,
              bankSessionId: BankLedgerService().currentBankSessionId,
            );
            await _sendBankResult(
              syncResult,
              transportType: _transportForIncomingPayload(payload),
            );
          } else {
            final sourceTransport = _transportForIncomingPayload(payload);
            final result = await BankLedgerService().ensurePlayer(
              playerId,
              kInitialBalance,
              deviceInstallationId: deviceInstallationId,
            );
            final handshake = <String, dynamic>{
              'type': 'handshake',
              'targetPlayerId': playerId,
              'avatarId': session.avatarId,
              'colorId': session.colorId,
              'gameId': 'monopoly',
              'name': session.name,
              'bankTxId': result.transactionId,
              'eventType': result.eventType,
              'amount': result.amount,
              'bankSessionId': BankLedgerService().currentBankSessionId,
              ...result.account.toClientState(),
            };
            P2PService().setTransport(sourceTransport);
            try {
              await P2PService().sendPayload(handshake);
            } on TransportUnavailableException {
              // La identidad BLE se repite al terminar la suscripción.
            }
        }
      }
    }

    if (session.isBank && type == 'bank_operation_request') {
        await _handleBankOperationRequest(payload);
        wallet.refreshHistory();
        return;
      }

      if (session.isBank && type == 'transfer_hold_request') {
        await _handleBankTransferHoldRequest(payload);
        wallet.refreshHistory();
        return;
      }

      if (type == 'handshake') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        if (!session.isHandshakeDone) {
          await session.applyHandshake(payload);
          _setBleClientIdentity();
          _triggerWelcomeAnimation(payload['name'] as String?);
        }
        await wallet.applyBankState(payload);
        try {
          await WidgetsBinding.instance.endOfFrame
              .timeout(const Duration(seconds: 1));
        } on TimeoutException {
          // El estado ya quedó persistido; la confirmación puede continuar.
        }
        await P2PService().sendPayload({
          'type': 'handshake_confirm',
          if (payload['bankTxId'] != null) 'bankTxId': payload['bankTxId'],
          'playerId': session.name,
          'name': session.name,
          'appliedBalance': wallet.balance,
          'deviceInstallationId': DeviceIdentityService.installationId,
        });
      } else if (type == 'handshake_confirm') {
        return;
      } else if (type == 'bank_state') {
        if (!session.isHandshakeDone) return;
        if (!_isPayloadForPlayer(payload, session.name)) return;
        await wallet.applyBankState(payload);
        final bankTxId = payload['bankTxId'] as String?;
        if (bankTxId != null && bankTxId.isNotEmpty) {
          try {
            await WidgetsBinding.instance.endOfFrame
                .timeout(const Duration(seconds: 1));
          } on TimeoutException {
            // El estado ya fue persistido y notificado; confirmamos igualmente.
          }
          await P2PService().sendPayload({
            'type': 'bank_state_ack',
            'bankTxId': bankTxId,
            'playerId': session.name,
            'name': session.name,
            'appliedBalance': wallet.balance,
            'deviceInstallationId': DeviceIdentityService.installationId,
          });
        }
        final requestId = payload['requestId'] as String?;
        if (requestId == _pendingBankOperationId) {
          final completer = _pendingBankOperationCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
      } else if (type == 'bank_operation_error') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        final message =
            (payload['message'] as String?) ?? 'El banco rechazó la operación.';
        final requestId = payload['requestId'] as String?;
        if (requestId == _pendingBankOperationId) {
          final completer = _pendingBankOperationCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.completeError(BankLedgerException(message));
          }
        } else {
          await _showBankOperationError(message);
        }
      } else if (type == 'bank_access_denied') {
        if (!_isPayloadForPlayer(payload, session.name)) return;
        _stopBleClient();
        await wallet.applyBankState(payload);
      }
    }, onError: (e, s) {
      if (mounted) _safeShowFriendlyError(e, s);
    });
  }

  bool _isPayloadForPlayer(Map<String, dynamic> payload, String playerId) {
    final target = payload['targetPlayerId'] as String?;
    return target == null || target == playerId;
  }

  String? _connectedPlayerIdForPayload(Map<String, dynamic> payload) {
    final deviceId = payload['_bleDeviceId'] as String?;
    if (deviceId != null) {
      for (final player
          in P2PService().bleTransport.connectedPlayersNotifier.value) {
        if (player.id == deviceId && player.displayName.trim().isNotEmpty) {
          return player.displayName;
        }
      }
    }
    final claimed = payload['playerId'] as String?;
    return claimed?.trim().isEmpty == false ? claimed : null;
  }

  Future<void> _disconnectBannedBleClient(String bleDeviceId) async {
    try {
      await P2PService().bleTransport
          .disconnectClient(bleDeviceId);
    } catch (_) {}
  }

  TransportType _transportForIncomingPayload(Map<String, dynamic> payload) {
    if (payload['_bleDeviceId'] != null) return TransportType.ble;
    return P2PService().currentType;
  }

  Future<void> _handleBankOperationRequest(Map<String, dynamic> payload) async {
    final playerId = _connectedPlayerIdForPayload(payload);
    if (playerId == null) return;
    final sourceTransport = _transportForIncomingPayload(payload);
    final requestId = payload['requestId'] as String?;

    try {
      final ledger = BankLedgerService();
      final operation = payload['operation'] as String?;
      final BankLedgerResult result;
      if (operation == 'invest') {
        final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
        final passes = (payload['passes'] as num?)?.toInt() ?? 0;
        result = await ledger.invest(playerId, amount, passes);
        NotificationService().show(
          '$playerId invirtió ${formatMoney(amount)} a $passes pases por GO',
          backgroundColor: kGold,
          duration: const Duration(seconds: 4),
          dedupeKey: 'invest-$playerId',
        );
      } else if (operation == 'withdraw_investment') {
        result = await ledger.withdrawInvestment(playerId);
        NotificationService().show(
          '$playerId retiró su inversión',
          backgroundColor: kGreen,
          duration: const Duration(seconds: 4),
          dedupeKey: 'withdraw-$playerId',
        );
      } else {
        throw const BankLedgerException('Operación bancaria desconocida.');
      }
      await _sendBankResult(
        result,
        transportType: sourceTransport,
        requestId: requestId,
      );
    } on BankLedgerException catch (error) {
      await _sendBankError(
        playerId,
        error.message,
        transportType: sourceTransport,
        requestId: requestId,
      );
    }
  }

  Future<void> _sendBankResult(
    BankLedgerResult result, {
    TransportType transportType = TransportType.ble,
    String? requestId,
  }) async {
    final payload = result.toClientPayload();
    if (requestId != null) payload['requestId'] = requestId;
    final completer = Completer<Map<String, dynamic>>();
    _bankDeliveryAcks[result.transactionId] = completer;
    try {
      P2PService().setTransport(transportType);
      await P2PService().sendPayload(payload);

      final confirmation =
          await completer.future.timeout(const Duration(seconds: 12));
      final confirmedPlayer = confirmation['playerId'] as String?;
      final confirmedBalance =
          (confirmation['appliedBalance'] as num?)?.toDouble();
      if (confirmedPlayer != result.account.playerId ||
          confirmedBalance == null ||
          (confirmedBalance - result.account.balance).abs() >= 0.001) {
        throw TransportUnavailableException(
          'El jugador respondió, pero no confirmó el saldo esperado.',
        );
      }
    } on TimeoutException {
      throw TransportUnavailableException(
        'El jugador no confirmó que recibió y mostró la operación.',
      );
    } finally {
      _bankDeliveryAcks.remove(result.transactionId);
    }
  }

  Future<void> _sendBankError(
    String playerId,
    String message, {
    TransportType transportType = TransportType.ble,
    String? requestId,
  }) async {
    final payload = {
      'type': 'bank_operation_error',
      'bankSessionId': BankLedgerService().currentBankSessionId,
      'targetPlayerId': playerId,
      'message': message,
      if (requestId != null) 'requestId': requestId,
    };
    P2PService().setTransport(transportType);
    await P2PService().sendPayload(payload);
  }

  Future<void> _sendBlockedDeviceState(
    String playerId, {
    required TransportType transportType,
  }) async {
    final payload = <String, dynamic>{
      'type': 'bank_access_denied',
      'bankSessionId': BankLedgerService().currentBankSessionId,
      'targetPlayerId': playerId,
      'balance': 0,
      'isBankrupt': true,
      'eventType': 'bankruptcy_blocked',
      'amount': 0,
      'vaultInvestedAmount': 0,
      'vaultGeneratedAmount': 0,
      'vaultTargetPasses': 0,
      'vaultCurrentPasses': 0,
    };
    P2PService().setTransport(transportType);
    await P2PService().sendPayload(payload);
  }

  Future<void> _showBankOperationError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Operación rechazada'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestBankOperation(Map<String, dynamic> request) async {
    final session = context.read<SessionProvider>();
    final transport = P2PService().bleTransport;
    if (!session.isHandshakeDone || !transport.clientConnectedNotifier.value) {
      throw TransportUnavailableException(
        'Debes estar conectado al banco y completar el handshake.',
      );
    }
    if (_pendingBankOperationCompleter != null) {
      throw const BankLedgerException(
        'Ya hay una operación bancaria en proceso.',
      );
    }

    final requestId =
        '${session.name}-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<void>();
    _pendingBankOperationId = requestId;
    _pendingBankOperationCompleter = completer;
    P2PService().setTransport(TransportType.ble);
    try {
      await P2PService().sendPayload({
        'type': 'bank_operation_request',
        'requestId': requestId,
        'playerId': session.name,
        'deviceInstallationId': DeviceIdentityService.installationId,
        ...request,
      });
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'El banco no confirmó la operación. Intenta nuevamente.',
        ),
      );
    } finally {
      if (identical(_pendingBankOperationCompleter, completer)) {
        _pendingBankOperationCompleter = null;
        _pendingBankOperationId = null;
      }
    }
  }

  Future<void> _handleBankTransferHoldRequest(
      Map<String, dynamic> payload) async {
    final sourceTransport = _transportForIncomingPayload(payload);
    final sourcePlayerId = _connectedPlayerIdForPayload(payload);
    if (sourcePlayerId == null || !mounted) return;
    if (_bankTransferHoldDialogOpen) {
      await _sendBankError(
        sourcePlayerId,
        'El banco ya está procesando otra transferencia.',
        transportType: sourceTransport,
      );
      return;
    }
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
    if (!amount.isFinite || amount <= 0) return;

    final fromName = sourcePlayerId;
    late final BankLedgerResult held;
    try {
      held = await BankLedgerService().debit(
        sourcePlayerId,
        amount,
        type: 'transfer_held',
        counterpartyId: 'Banco',
      );
      await _sendBankResult(held, transportType: sourceTransport);
    } on BankLedgerException catch (error) {
      await _sendBankError(
        sourcePlayerId,
        error.message,
        transportType: sourceTransport,
      );
      return;
    }
    if (!mounted) return;
    _bankTransferHoldDialogOpen = true;
    _dialogActive = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var sending = false;
        var completed = false;
        var settled = false;
        var message =
            'Acerca el celular del jugador receptor y pulsa entregar.';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> deliver() async {
              if (sending || completed) return;
              setDialogState(() {
                sending = true;
                message = 'Buscando al jugador receptor en contacto...';
              });

              try {
                var players = P2PService().bleTransport.connectedPlayersNotifier.value
                    .where((p) => p.subscribed && p.playing).toList();
                if (players.isEmpty) {
                  players = P2PService().bleTransport.connectedPlayersNotifier.value
                      .where((p) => p.subscribed).toList();
                }
                final String? receiverName = players.isNotEmpty ? players.first.displayName : null;
                if (receiverName == null) {
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    sending = false;
                    message =
                        'No se detectó un jugador listo. Acércalo e intenta de nuevo.';
                  });
                  return;
                }

                if (!ctx.mounted) return;
                setDialogState(() {
                  message = 'Entregando dinero a $receiverName...';
                });
                final delivered = await BankLedgerService().credit(
                  receiverName,
                  amount,
                  type: 'transfer_received',
                  counterpartyId: fromName,
                );
                await _sendBankResult(
                  delivered,
                  transportType: sourceTransport,
                );
                if (!ctx.mounted) return;
                setDialogState(() {
                  sending = false;
                  completed = true;
                  settled = true;
                  message = 'Proceso completado con el jugador $receiverName.';
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                });
              } catch (e, s) {
                if (!mounted || !ctx.mounted) return;
                _safeShowFriendlyError(e, s);
                setDialogState(() {
                  sending = false;
                  message = 'No se pudo entregar el dinero. Intenta de nuevo.';
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
                width: 260,
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
                    const SizedBox(height: 10),
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
                          message,
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
                    onPressed: sending
                        ? null
                        : () async {
                            SoundService.playClick();
                            if (!settled) {
                              setDialogState(() => sending = true);
                              final refunded = await BankLedgerService().credit(
                                sourcePlayerId,
                                amount,
                                type: 'transfer_cancelled',
                                counterpartyId: 'Banco',
                              );
                              await _sendBankResult(
                                refunded,
                                transportType: sourceTransport,
                              );
                              settled = true;
                            }
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                          },
                    child: const Text('Cerrar'),
                  ),
                SizedBox(
                  width: completed ? double.infinity : 150,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: completed || sending ? null : deliver,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: completed ? kGreen : kGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: sending
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
      _dialogActive = false;
      _bankTransferHoldDialogOpen = false;
    });
  }

  Future<void> _startBleClient() async {
    if (_bleScanning) return;
    final transport = P2PService().bleTransport;
    final ready = await _ensureBleReady(transport);
    if (!ready || !mounted) return;

    if (P2PService().currentType != TransportType.ble) {
      P2PService().setTransport(TransportType.ble);
    }
    _setBleClientIdentity();
    _bleScanning = true;
    setState(() {});
    try {
      await P2PService().startReceiving(null);
    } catch (e, s) {
      _bleScanning = false;
      if (mounted) _safeSetState(() {});
      if (mounted) _safeShowFriendlyError(e, s);
    }
  }

  Future<void> _stopBleClient() async {
    _userRequestedBleDisconnect = true;
    _bleScanning = false;
    try {
      await P2PService().bleTransport.stopClientScan();
      if (mounted) _safeSetState(() {});
    } finally {
      _userRequestedBleDisconnect = false;
    }
  }

  Future<void> _connectToBleBank(BleBankDevice bank) async {
    SoundService.playClick();
    _setBleClientIdentity();
    try {
      await P2PService().bleTransport.connectToBank(bank);
    } catch (e, s) {
      if (mounted) _safeShowFriendlyError(e, s);
    }
  }

  void _setBleClientIdentity() {
    final session = context.read<SessionProvider>();
    P2PService().bleTransport.setClientIdentity(
          name: session.name,
          avatarId: session.avatarId,
          colorId: session.colorId,
          isHandshakeDone: session.isHandshakeDone,
        );
  }

  void _listenToBankruptcy() {
    final wallet = context.read<WalletController>();
    _bankruptNotifierRef = wallet.bankruptNotifier;
    _bankruptListener ??= () {
      if (wallet.bankruptNotifier.value && mounted) {
        _openBankruptcyScreen();
      }
    };
    wallet.bankruptNotifier.addListener(_bankruptListener!);
    _bankruptListener!();

    _txSub?.cancel();
    _txSub = wallet.txStream.listen((event) {
      if (event == TxType.largeTransfer && mounted) {
        _confettiCtrl.play();
      }
    });
  }

  void _showToast(String msg, Color color) {
    NotificationService().show(msg, backgroundColor: color);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    if (_dialogActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  Future<void> _safeShowFriendlyError(dynamic error, [StackTrace? stack]) async {
    final friendly = await ErrorTranslatorService().translate(error, stack);
    if (!mounted) return;
    if (friendly.severity == ErrorSeverity.error ||
        friendly.severity == ErrorSeverity.critical) {
      NotificationService().show(
        friendly.message,
        backgroundColor: kRed,
        duration: const Duration(seconds: 5),
      );
    } else {
      NotificationService().show(
        friendly.message,
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> _showPlayerTransferDialog(
    WalletController wallet,
    Color brandColor,
  ) async {
    final amountCtrl = TextEditingController();
    final session = context.read<SessionProvider>();

    _dialogActive = true;
    try {
    await showPremiumDialog<void>(
      context: context,
      child: Builder(
        builder: (dialogContext) => AlertDialog(
          backgroundColor: kBgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Transferir a jugador',
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El banco retendra este dinero hasta que el jugador receptor acerque su celular.',
                style: TextStyle(color: kTextSecondary, height: 1.35),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: '\$ ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                SoundService.playClick();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                foregroundColor: brandColor.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
              onPressed: () async {
                SoundService.playClick();
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) {
                  _showToast('Ingresa un monto valido.', kRed);
                  return;
                }
                final transportType = P2PService().currentType;
                if (transportType == TransportType.ble &&
                    !P2PService().bleTransport.clientConnectedNotifier.value) {
                  _showToast('Conéctate al banco por BLE primero.', kRed);
                  return;
                }

                try {
                  final request = {
                    'type': 'transfer_hold_request',
                    'amount': amount,
                    'fromPlayerId': session.name,
                    'fromName': session.name,
                    'deviceInstallationId':
                        DeviceIdentityService.installationId,
                  };
                  P2PService().setTransport(TransportType.ble);
                  await P2PService().sendPayload(request);
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                } catch (e, s) {
                  if (mounted) _safeShowFriendlyError(e, s);
                }
              },
              child: const Text('Retener en banco'),
            ),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    } finally {
      _dialogActive = false;
    }
  }

  void _listenToTierEvolution() {
    final wallet = context.read<WalletController>();
    _tierSub?.cancel();
    _tierSub = wallet.tierStream.listen((newTier) {
      if (!mounted || _evolutionDialogOpen) return;
      final pending = _pendingCelebrationTier;
      if (pending == null || newTier.index > pending.index) {
        _pendingCelebrationTier = newTier;
      }
      _tierCelebrationTimer?.cancel();
      _tierCelebrationTimer = Timer(const Duration(milliseconds: 300), () {
        final tier = _pendingCelebrationTier;
        _pendingCelebrationTier = null;
        if (mounted && tier != null && !_evolutionDialogOpen) {
          _showEvolutionAnimation(tier);
        }
      });
    });
  }

  void _showEvolutionAnimation(CardTier tier) async {
    if (_evolutionDialogOpen || !mounted) return;
    _evolutionDialogOpen = true;
    // Pokemon-style evolution feel
    HapticFeedback.vibrate();
    SoundService.playSuccess();

    String tierName = "";
    Color accentColor = Colors.white;
    switch (tier) {
      case CardTier.gold:
        tierName = "GOLD";
        accentColor = const Color(0xFFBF953F);
        break;
      case CardTier.platinum:
        tierName = "PLATINUM";
        accentColor = const Color(0xFFE0E0E0);
        break;
      case CardTier.black:
        tierName = "ULTIMATE BLACK";
        accentColor = Colors.blueAccent;
        break;
      default:
        tierName = "STANDARD";
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.9),
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (ctx, anim1, anim2) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AnimatedEntry(
                    delay: Duration(milliseconds: 200),
                    child: Text(
                      "¡TU TARJETA ESTÁ EVOLUCIONANDO!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4),
                    ),
                  ),
                  const SizedBox(height: 40),
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.5, end: 1.2).animate(
                        CurvedAnimation(
                            parent: anim1, curve: Curves.elasticOut)),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: accentColor.withValues(alpha: 0.5),
                              blurRadius: 50,
                              spreadRadius: 10)
                        ],
                      ),
                      child: Icon(Icons.auto_awesome_rounded,
                          size: 120, color: accentColor),
                    ),
                  ),
                  const SizedBox(height: 40),
                  AnimatedEntry(
                    delay: const Duration(milliseconds: 600),
                    child: Column(
                      children: [
                        const Text(
                          "¡FELICIDADES!",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "HAS ALCANZADO EL NIVEL $tierName",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: accentColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                  ElevatedButton(
                    onPressed: () {
                      _confettiCtrl.play();
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text("VER MI NUEVA TARJETA",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
        transitionBuilder: (ctx, anim1, anim2, child) {
          return FadeTransition(opacity: anim1, child: child);
        },
      );
    } finally {
      _evolutionDialogOpen = false;
    }
  }

  void _openBankruptcyScreen() {
    if (_bankruptcyScreenOpen || !mounted) return;
    final session = context.read<SessionProvider>();
    if (session.isBank) return;
    _bankruptcyScreenOpen = true;
    unawaited(P2PService().shutdown());
    unawaited(
      Navigator.of(context)
          .push<void>(
            GameFadeRoute(
              page: BankruptcyScreen(playerName: session.name),
            ),
          )
          .whenComplete(() => _bankruptcyScreenOpen = false),
    );
  }

  Future<void> _triggerWelcomeAnimation(String? name) async {
    _safeSetState(() {
      _showWelcome = true;
    });
    await _welcomeCtrl.forward();
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      await _welcomeCtrl.reverse();
      setState(() => _showWelcome = false);
    }
  }

  Future<void> _hideWelcome() async {
    if (_showWelcome) {
      await _welcomeCtrl.reverse();
      _safeSetState(() => _showWelcome = false);
    }
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
    P2PService().shutdown();
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
      P2PService().bleTransport.serverActiveNotifier
          .removeListener(bankServerListener);
    }
    _announcedBleConnections.clear();
    _pulseCtrl.dispose();
    _welcomeCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final session = context.watch<SessionProvider>();
    final stats = context.watch<StatsProvider>();
    final history = wallet.history;

    if (session.role.isNotEmpty && !_isExiting) {
      _lastRole = session.role;
      _lastColor = session.color;
      _lastName = session.name;
      _lastAvatarId = session.avatarId;
      _lastColorId = int.tryParse(session.colorId) ?? 0;
      _lastBalance = wallet.rawBalance.value;
    }

    final displayColor = _lastColor ?? kGreen;
    final displayName = _lastName ?? '';
    final displayAvatar = _lastAvatarId ?? '';
    final displayRole = _lastRole ?? 'cliente';
    final displayColorId = _lastColorId ?? 0;
    final displayBalance = _lastBalance ?? 0.0;
    final isBank = displayRole == 'banco';
    final bleConnected = isBank ||
        P2PService().currentType != TransportType.ble ||
        P2PService().bleTransport.clientConnectedNotifier.value;
    final playerReady =
        isBank || (session.isHandshakeDone && bleConnected);
    final shownBalance = playerReady ? displayBalance : 0.0;
    // Si el banco no tiene Bluetooth, mostrar pantalla limpia como al inicio
    final bankBleOk = !isBank || P2PService().bleTransport.isEnabled;
    final shownTier = playerReady ? wallet.currentTier : CardTier.standard;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final session = context.read<SessionProvider>();
        _confirmExit(session);
      },
      child: Scaffold(
        backgroundColor: kBgDark,
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            isBank && bankBleOk && !kBankTabsActive
                ? FloatingActionButton.extended(
                    heroTag: 'bank_panel_btn',
                    onPressed: () async {
                      SoundService.playClick();
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        GameSlideRoute(
                          begin: const Offset(0, 0.12),
                          page: const BankScreen(),
                        ),
                      );
                      if (mounted) {
                        _bankStatsListener?.call();
                        setState(() {});
                      }
                    },
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                    icon: const Icon(Icons.account_balance_rounded),
                    label: const Text(
                      'Panel Banco',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  )
                : playerReady && !_showWelcome
                    ? FloatingActionButton.extended(
                        heroTag: 'transfer_to_bank_btn',
                        onPressed: () {
                          SoundService.playClick();
                          _showPlayerTransferDialog(wallet, displayColor);
                        },
                        backgroundColor: displayColor,
                        foregroundColor: displayColor.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text(
                          'Transferir',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    : const SizedBox.shrink(),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: MonopolyBackground(
          child: PlayerColorBackdrop(
            color: displayColor,
            child: Stack(
              children: [
                Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: CustomScrollView(
                    slivers: [
                      _buildAppBar(displayAvatar, displayColor, displayName,
                          displayRole, isBank),
                      if (!isBank)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 100),
                            child: _buildBalanceCard(
                                shownBalance,
                                displayColor,
                                displayName,
                                displayColorId,
                                _lastHistory,
                                isBank,
                                tier: shownTier,
                              ),
                          ),
                        ),
                      if (!isBank && playerReady)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 200),
                            child: _buildVaultSection(wallet, displayColor),
                          ),
                        ),
                      if (playerReady)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 300),
                            child: _buildStatsRow(stats, displayColor),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: AnimatedEntry(
                          delay: const Duration(milliseconds: 400),
                          child: ValueListenableBuilder<TransportType>(
                            valueListenable: P2PService().typeNotifier,
                            builder: (context, type, _) {
                              return _buildConnectionPanel(
                                  displayColor, type, isBank);
                            },
                          ),
                        ),
                      ),
                      if (isBank && bankBleOk)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 450),
                            child: _buildConnectedPlayersPanel(displayColor),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: TransportSelector(),
                        ),
                      ),
                      if (playerReady)
                        SliverToBoxAdapter(
                          child: AnimatedEntry(
                            delay: const Duration(milliseconds: 500),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Row(
                                children: [
                                  const Text(
                                    'HISTORIAL',
                                  style: TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 12,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: kBgCard,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${history.length}',
                                    style: const TextStyle(
                                        color: kTextSecondary, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (playerReady && history.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_rounded,
                                    color: Color(0xFF4B5563), size: 48),
                                SizedBox(height: 12),
                                Text(
                                  'Sin transacciones aún',
                                  style: TextStyle(color: kTextSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (playerReady)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => TransactionTile(tx: history[i]),
                            childCount: history.length,
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                            height: 80 + MediaQuery.of(context).padding.bottom),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiCtrl,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [kGold, kGreen, Colors.white, Colors.blue],
                  numberOfParticles: 50,
                  gravity: 0.1,
                ),
              ),
              if (_showWelcome)
                _buildWelcomeOverlay(displayAvatar, displayColor, displayName),
            ],
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildNetworkTransferAlert(
      String stateStr, String userName, bool isBank) {
    Color color = kGold;
    String label = '';
    String sub = '';
    bool showAction = false;

    if (stateStr == 'waitingSender' && !isBank) {
      color = kRed;
      label = 'EMISOR: ENTREGAR DINERO';
      sub = 'Toca para confirmar el envío al banco';
      showAction = true;
    } else if (stateStr == 'waitingReceiver' && !isBank) {
      color = kGreen;
      label = 'RECEPTOR: RECIBIR DINERO';
      sub = 'Dinero listo en el banco. Toca para cobrar';
      showAction = true;
    } else if (stateStr == 'holding') {
      color = kGold;
      label = 'DINERO RETENIDO EN BANCO';
      sub = 'Procesando transferencia...';
    } else {
      return const SizedBox();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.2)),
                    Text(sub,
                        style: const TextStyle(
                            color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (showAction) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  SoundService.playClick();
                  try {
                    JugadorClient().confirmAction(userName);
                  } catch (e, s) {
                    if (context.mounted) _safeShowFriendlyError(e, s);
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.black),
                child: const Text('CONFIRMAR ACCIÓN FÍSICA',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWelcomeOverlay(String avatarId, Color color, String name) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: FadeTransition(
          opacity: _welcomeOpacity,
          child: ScaleTransition(
            scale: _welcomeScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: color.withValues(alpha: 0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: AnimatedAvatar(
                    emoji: avatarId,
                    size: 104,
                    glowColor: color,
                    showIdle: true,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '¡BIENVENIDO!',
                  style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 48),
                IconButton(
                  onPressed: () {
                    SoundService.playClick();
                    _hideWelcome();
                  },
                  icon: const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 64),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(
      String avatarId, Color color, String name, String role, bool isBank) {
    final width = MediaQuery.sizeOf(context).width;
    final compactActions = width < 390;
    final title =
        isBank ? 'Banca Central' : (name.isNotEmpty ? name : 'Mi Billetera');
    final subtitle =
        role.toLowerCase() == 'cliente' ? 'JUGADOR' : role.toUpperCase();

    return SliverAppBar(
      backgroundColor: kBgDark,
      expandedHeight: 0,
      floating: true,
      leadingWidth: 0,
      titleSpacing: 12,
      title: Row(
        children: [
          AnimatedAvatar(
            emoji: avatarId,
            size: compactActions ? 32 : 36,
            glowColor: color,
            showIdle: false,
          ),
          SizedBox(width: compactActions ? 8 : 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kTextPrimary,
                    fontSize: compactActions ? 14 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!compactActions) ...[
          IconButton(
            icon: const Icon(Icons.bluetooth_rounded, color: kTextSecondary),
            tooltip: 'BLE Debug',
            onPressed: _openBleDebug,
          ),
        ],
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: kRed),
          tooltip: 'Cerrar Sesión',
          onPressed: () {
            SoundService.playClick();
            _confirmExit(context.read<SessionProvider>());
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
          onPressed: () {
            SoundService.playClick();
            setState(() {});
          },
        ),
        if (compactActions)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: kTextSecondary),
            tooltip: 'Más opciones',
            color: kBgCard,
            onSelected: (value) {
              if (value == 'ble') _openBleDebug();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'ble',
                child: Text('BLE Debug'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _openBleDebug() async {
    SoundService.playClick();
    await P2PService().shutdown();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BleTestScreen()),
    );
  }

  void _confirmExit(SessionProvider session) {
    showPremiumDialog(
      context: context,
      child: AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cerrar sesión?',
            style: TextStyle(color: kTextPrimary)),
        content: const Text(
          'Se borrarán todos los datos de esta partida y volverás a la selección de roles.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(context);
            },
            child:
                const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _isExiting = true);
              Navigator.pop(context);
              session.clearSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(
    double balance,
    Color color,
    String name,
    int colorId,
    List<double> history,
    bool isBank, {
    CardTier? tier,
  }) {
    final wallet = context.read<WalletController>();
    return ValueListenableBuilder<int>(
      valueListenable: wallet.balanceDecreaseShake,
      builder: (context, shakeCount, _) {
        return _PremiumCreditCard(
          balance: balance,
          name: name,
          color: color,
          colorId: colorId,
          history: history,
          isBank: isBank,
          tier: tier,
        )
            .animate(key: ValueKey('card-$shakeCount'))
            .shake(duration: 400.ms)
            .fade();
      },
    );
  }

  Widget _buildVaultSection(WalletController wallet, Color color) {
    return ValueListenableBuilder<double>(
        valueListenable: wallet.vaultInvestedAmount,
        builder: (context, invested, _) {
          return ValueListenableBuilder<double>(
              valueListenable: wallet.vaultGeneratedAmount,
              builder: (context, generated, _) {
                return ValueListenableBuilder<int>(
                    valueListenable: wallet.vaultCurrentPasses,
                    builder: (context, currentPasses, _) {
                      return ValueListenableBuilder<int>(
                          valueListenable: wallet.vaultTargetPasses,
                          builder: (context, targetPasses, _) {
                            final hasInvestment = invested > 0;
                            return Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: kBgCard,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.security_rounded,
                                          color: Colors.blueGrey),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'BÓVEDA DE INVERSIÓN',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (hasInvestment)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: targetPasses > 0 &&
                                                    currentPasses >=
                                                        targetPasses
                                                ? kGreenGlow.withValues(
                                                    alpha: 0.2)
                                                : Colors.orange
                                                    .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            targetPasses > 0 &&
                                                    currentPasses >=
                                                        targetPasses
                                                ? 'COMPLETADO'
                                                : 'EN PROCESO',
                                            style: TextStyle(
                                              color: targetPasses > 0 &&
                                                      currentPasses >=
                                                          targetPasses
                                                  ? kGreenGlow
                                                  : Colors.orange,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (!hasInvestment) ...[
                                    const Text(
                                      'Invierta su dinero a plazo fijo. Obtenga altos retornos bloqueando su saldo por una determinada cantidad de cruces por GO.',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          SoundService.playClick();
                                          _showInvestDialog(wallet, color);
                                        },
                                        icon: const Icon(
                                            Icons.rocket_launch_rounded),
                                        label: const Text('Comenzar Inversión'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: color,
                                          foregroundColor:
                                              color.computeLuminance() > 0.5
                                                  ? Colors.black
                                                  : Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                      ),
                                    )
                                  ] else ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Capital Invertido',
                                                style: TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11)),
                                            Text(formatMoney(invested),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 20,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text('Rendimiento',
                                                style: TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11)),
                                            Text('+${formatMoney(generated)}',
                                                style: const TextStyle(
                                                    color: kGreenGlow,
                                                    fontSize: 20,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: targetPasses > 0
                                                  ? (currentPasses /
                                                          targetPasses)
                                                      .clamp(0.0, 1.0)
                                                  : 0.0,
                                              minHeight: 8,
                                              backgroundColor: Colors.white10,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '$currentPasses / $targetPasses GO',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    if (currentPasses >= targetPasses)
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            SoundService.playClick();
                                            _showWithdrawDialog(wallet, color);
                                          },
                                          icon: const Icon(
                                              Icons.account_balance_wallet_rounded,
                                              size: 18),
                                          label: const Text('Retirar Ganancias'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: color,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 18, vertical: 14),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12, horizontal: 14),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.orange.withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.lock_rounded,
                                                color: Colors.orange, size: 16),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Inversión bloqueada. Completa los pases por GO para retirar.',
                                                style: TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            );
                          });
                    });
              });
        });
  }

  void _showInvestDialog(WalletController wallet, Color brandColor) {
    final amountCtrl = TextEditingController();
    int selectedPasses = 3;
    bool submitting = false;

    showPremiumDialog(
      context: context,
      child: StatefulBuilder(builder: (context, setStateSB) {
        final val = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
        double getRate(int passes) {
          switch (passes) {
            case 1:
              return 0.05;
            case 2:
              return 0.07;
            case 3:
              return 0.10;
            case 4:
              return 0.12;
            case 5:
              return 0.15;
            default:
              return 0.05;
          }
        }

        final rate = getRate(selectedPasses);
        final expectedTotal = val > 0 ? val * rate * selectedPasses : 0;
        final wouldEmptyBalance = val > 0 && (wallet.balance - val) <= 0;

        return AlertDialog(
          backgroundColor: kBgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nueva Inversión',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Acerca tu dispositivo al banco para enviar la solicitud de inversión.',
                    style: TextStyle(color: kGold, fontSize: 12, height: 1.35)),
                const SizedBox(height: 16),
                const Text('Monto a Invertir',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setStateSB(() {}),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    filled: true,
                    fillColor: kBgDark,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                if (wouldEmptyBalance) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No puedes invertir todo tu saldo. Debe quedar al menos \$1 en tu cuenta.',
                    style: TextStyle(color: kRed, fontSize: 11, height: 1.3),
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Plazo (Pases por GO)',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (index) {
                    final passes = index + 1;
                    final isSelected = selectedPasses == passes;
                    return GestureDetector(
                      onTap: () {
                        SoundService.playClick();
                        setStateSB(() => selectedPasses = passes);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? brandColor : kBgDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isSelected ? brandColor : Colors.white10),
                        ),
                        child: Text(
                          '$passes',
                          style: TextStyle(
                            color: isSelected
                                ? (brandColor.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white)
                                : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('Rendimiento por Pase: ${(rate * 100).round()}%',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('Ganancia Estimada: ${formatMoney(expectedTotal)}',
                          style: const TextStyle(
                              color: kGreenGlow,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting
                    ? null
                    : () {
                        SoundService.playClick();
                        Navigator.pop(context);
                      },
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                foregroundColor: brandColor.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
              onPressed: (submitting || wouldEmptyBalance)
                  ? null
                  : () async {
                      SoundService.playClick();
                      final finalVal = double.tryParse(
                              amountCtrl.text.replaceAll(',', '')) ??
                          0;
                      if (finalVal > 0) {
                        setStateSB(() => submitting = true);
                        try {
                          await _requestBankOperation({
                            'operation': 'invest',
                            'amount': finalVal,
                            'passes': selectedPasses,
                          });
                          if (context.mounted) Navigator.pop(context);
                        } catch (e, s) {
                          if (context.mounted) _safeShowFriendlyError(e, s);
                        } finally {
                          if (context.mounted) {
                            setStateSB(() => submitting = false);
                          }
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Invertir'),
            ),
          ],
        );
      }),
    );
  }

  void _showWithdrawDialog(WalletController wallet, Color brandColor) {
    showPremiumDialog(
        context: context,
        child: AlertDialog(
          backgroundColor: kBgCard,
          title: Text('Retiro de Inversión',
              style: TextStyle(color: brandColor, fontWeight: FontWeight.bold)),
          content: const Text(
            '¡Enhorabuena! Has cumplido el plazo de tu inversión. Se acreditará tu capital más los intereses generados a tu cuenta principal.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  SoundService.playClick();
                  Navigator.pop(context);
                },
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: brandColor,
                  foregroundColor: Colors.white),
              onPressed: () async {
                SoundService.playClick();
                try {
                  await _requestBankOperation({
                    'operation': 'withdraw_investment',
                  });
                  if (mounted) Navigator.pop(context);
                } catch (e, s) {
                  if (mounted) _safeShowFriendlyError(e, s);
                }
              },
              child: const Text('Liquidar Inversión'),
            ),
          ],
        ));
  }

  Widget _buildStatsRow(StatsProvider stats, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _StatChip(
            label: 'Volumen',
            value: _compact(stats.totalVolume),
            icon: Icons.payments_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Tx',
            value: stats.txCount.toString(),
            icon: Icons.history_rounded,
            color: color,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Pass GO',
            value: 'x${stats.passGoCount}',
            icon: Icons.flag_rounded,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel(
      Color color, TransportType currentTransport, bool isBank) {
    if (currentTransport == TransportType.ble) {
      if (isBank) return _buildBleBankPanel();
      return _buildBleClientPanel(color);
    }
    // Fallback: always prefer BLE
    if (isBank) return _buildBleBankPanel();
    return _buildBleClientPanel(color);
  }

  Widget _buildConnectedPlayersPanel(Color color) {
    final transport = P2PService().bleTransport;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ValueListenableBuilder<List<BleConnectedPlayer>>(
        valueListenable: transport.connectedPlayersNotifier,
        builder: (context, blePlayers, _) {
          final total = blePlayers.length;

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
                    Icon(Icons.groups_rounded, color: color, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Jugadores conectados',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '$total',
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (total == 0) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Sin jugadores activos',
                    style: TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  ...blePlayers.map(_buildBleConnectedPlayerTile),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBleConnectedPlayerTile(BleConnectedPlayer player) {
    final quality = player.rssi == null
        ? player.qualityLabel
        : '${player.qualityLabel} - ${player.rssi} dBm';
    final detail =
        '${player.playing ? 'Jugando' : 'Esperando handshake'} - $quality';
    return GestureDetector(
      onTap: () => _showPlayerInfoDialog(player),
      child: _ConnectedPlayerTile(
        name: player.displayName,
        deviceName: player.displayDeviceName,
        transport: 'BLE',
        detail: detail,
        color: player.playing ? player.qualityColor : Colors.blue,
        icon: Icons.bluetooth_connected_rounded,
      ),
    );
  }

  void _showPlayerInfoDialog(BleConnectedPlayer player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: player.qualityColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.bluetooth_connected_rounded,
                  color: player.qualityColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                player.displayName,
                style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Nombre', player.name.isNotEmpty ? player.name : '-'),
              _infoRow('Dispositivo', player.displayDeviceName),
              _infoRow('ID Instalación', player.deviceInstallationId.isNotEmpty
                  ? player.deviceInstallationId
                  : '-'),
              _infoRow('BLE Device ID', player.id),
              const SizedBox(height: 8),
              _infoRow('Handshake',
                  player.playing ? 'Completado' : 'Pendiente'),
              _infoRow('Suscripción GATT',
                  player.subscribed ? 'Activa' : 'Inactiva'),
              _infoRow('Última actividad',
                  '${player.lastSeen.hour.toString().padLeft(2, '0')}:'
                      '${player.lastSeen.minute.toString().padLeft(2, '0')}:'
                      '${player.lastSeen.second.toString().padLeft(2, '0')}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                  color: kTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureBleReady(BleTransport transport) async {
    var status = await transport.refreshAvailability();
    if (status == BleAvailabilityStatus.ready) return true;
    if (!mounted) return false;

    if (status == BleAvailabilityStatus.noHardware) {
      _showToast('Este dispositivo no tiene Bluetooth LE disponible.', kRed);
      return false;
    }

    if (status == BleAvailabilityStatus.missingPermissions) {
      final allow = await _confirmAction(
        title: 'Permisos de Bluetooth',
        message:
            'Para usar la conexión BLE necesito permisos de Bluetooth. ¿Quieres permitirlos ahora?',
        confirmLabel: 'Permitir',
      );
      if (allow != true || !mounted) return false;

      await transport.requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));
      status = await transport.refreshAvailability();
      if (status == BleAvailabilityStatus.ready) return true;
      if (status == BleAvailabilityStatus.bluetoothOff) {
        return _askToOpenBleSettings(transport);
      }
      _showToast(
          'Permisos de Bluetooth pendientes. Revisa los permisos de la app.',
          kRed);
      return false;
    }

    if (status == BleAvailabilityStatus.bluetoothOff) {
      return _askToOpenBleSettings(transport);
    }

    _showToast(
        'No pude verificar Bluetooth. Revisa los ajustes e intenta de nuevo.',
        kRed);
    return false;
  }

  Future<bool> _askToOpenBleSettings(BleTransport transport) async {
    final open = await _confirmAction(
      title: 'Bluetooth apagado',
      message:
          'Para conectarte por BLE debes activar Bluetooth. ¿Quieres abrir los ajustes para encenderlo?',
      confirmLabel: 'Abrir ajustes',
    );
    if (open == true && mounted) {
      await transport.openBleSettings();
    }
    return false;
  }

  Future<bool?> _confirmAction({
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

  Future<void> _reiniciarBleBanco() async {
    final transport = P2PService().bleTransport;
    try {
      await transport.stopServer();
    } catch (_) {}
    transport.connectedPlayersNotifier.value = const [];
    await transport.resetState();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final ready = await _ensureBleReady(transport);
    if (!ready || !mounted) return;
    await P2PService().startBleBankServer();
    P2PService().setTransport(TransportType.ble);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showBleDistanceSettings() {
    final transport = P2PService().bleTransport;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Configurar distancia',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800),
        ),
        content: ValueListenableBuilder<int>(
          valueListenable: transport.contactProfileIndexNotifier,
          builder: (context, index, _) {
            final profile = kBleContactProfiles[index];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.settings_input_antenna_rounded,
                        color: Colors.blue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        profile.label,
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  profile.helper,
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.blue,
                    inactiveTrackColor: kBorder,
                    thumbColor: kGold,
                    overlayColor: kGold.withValues(alpha: 0.12),
                    tickMarkShape:
                        const RoundSliderTickMarkShape(tickMarkRadius: 3),
                    activeTickMarkColor: kTextPrimary,
                    inactiveTickMarkColor: kTextSecondary,
                    valueIndicatorColor: kBgDark,
                    valueIndicatorTextStyle: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: (kBleContactProfiles.length - 1).toDouble(),
                    divisions: kBleContactProfiles.length - 1,
                    value: index.toDouble(),
                    label: profile.label,
                    onChanged: (value) {
                      SoundService.playClick();
                      transport.setContactProfileIndex(value.round());
                    },
                  ),
                ),
                const Row(
                  children: [
                    Text(
                      'Muy estricto',
                      style: TextStyle(color: kTextSecondary, fontSize: 11),
                    ),
                    Spacer(),
                    Text(
                      'Lejos',
                      style: TextStyle(color: kTextSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                SoundService.playClick();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Guardar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBleBankPanel() {
    final transport = P2PService().bleTransport;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: ValueListenableBuilder<bool>(
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
                        color:
                            active ? accent.withValues(alpha: 0.45) : kBorder,
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
                            if (active) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Configurar distancia',
                                onPressed: () {
                                  SoundService.playClick();
                                  _showBleDistanceSettings();
                                },
                                icon: const Icon(
                                  Icons.tune_rounded,
                                  color: kTextSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: active
                              ? Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color:
                                            accent.withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: accent.withValues(
                                              alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            connected
                                                ? Icons.link_rounded
                                                : Icons.sensors_rounded,
                                            color: accent,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              connected
                                                  ? 'Listo para operar con el jugador'
                                                  : 'Activo autom\u00e1ticamente',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: accent,
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          SoundService.playClick();
                                          _reiniciarBleBanco();
                                        },
                                        icon: const Icon(
                                            Icons.restart_alt_rounded,
                                            size: 16),
                                        label: const Text('Reiniciar BLE'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: kGold,
                                          side: const BorderSide(
                                              color: kGold),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ElevatedButton.icon(
                                  onPressed: () async {
                                    SoundService.playClick();
                                    final ready =
                                        await _ensureBleReady(transport);
                                    if (!ready || !mounted) return;
                                    await P2PService().startBleBankServer();
                                    P2PService()
                                        .setTransport(TransportType.ble);
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      size: 16),
                                  label: const Text('Iniciar Servidor BLE'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
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
      ),
    );
  }

  Widget _buildBleClientPanel(Color color) {
    final transport = P2PService().bleTransport;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: transport.clientConnectedNotifier,
        builder: (context, connected, _) {
          return ValueListenableBuilder<String>(
            valueListenable: transport.connectionStatusNotifier,
            builder: (context, status, _) {
              return ValueListenableBuilder<String>(
                valueListenable: transport.connectedDeviceNameNotifier,
                builder: (context, _, __) {
                  final connecting = status.startsWith('Conectando') ||
                      status.startsWith('Preparando');
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          connected ? color.withValues(alpha: 0.08) : kBgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: connected
                            ? color.withValues(alpha: 0.5)
                            : connecting
                                ? Colors.blue.withValues(alpha: 0.4)
                                : _bleScanning
                                    ? Colors.blue.withValues(alpha: 0.4)
                                    : kBorder,
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
                                  : connecting
                                      ? Icons.bluetooth_searching_rounded
                                      : _bleScanning
                                          ? Icons.bluetooth_searching_rounded
                                          : Icons.bluetooth_rounded,
                              color: connected
                                  ? color
                                  : connecting
                                      ? Colors.blue
                                      : _bleScanning
                                          ? Colors.blue
                                          : kTextSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    connected
                                        ? 'CONECTADO AL BANCO'
                                        : connecting
                                            ? 'CONECTANDO AL BANCO...'
                                            : _bleScanning
                                                ? 'CONECTANDO POR BLE...'
                                                : 'BLUETOOTH',
                                    style: TextStyle(
                                      color: connected
                                          ? color
                                          : connecting
                                              ? Colors.blue
                                              : _bleScanning
                                                  ? Colors.blue
                                                  : kTextSecondary,
                                      fontSize: 11,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (status.isNotEmpty)
                                    Text(
                                      status,
                                      style: TextStyle(
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
                                color: connected
                                    ? color
                                    : connecting
                                        ? Colors.blue
                                        : _bleScanning
                                            ? Colors.blue
                                            : kBorder,
                                boxShadow: (connected ||
                                        _bleScanning ||
                                        connecting)
                                    ? [
                                        BoxShadow(
                                          color:
                                              (connected ? color : Colors.blue)
                                                  .withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: connected || _bleScanning || connecting
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    SoundService.playClick();
                                    _stopBleClient();
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_disabled_rounded,
                                      size: 16),
                                  label: Text(connected
                                      ? 'Desconectar del Banco'
                                      : 'Cancelar conexión'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kRed,
                                    side: const BorderSide(color: kRed),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () {
                                    SoundService.playClick();
                                    _startBleClient();
                                  },
                                  icon: const Icon(
                                      Icons.bluetooth_searching_rounded,
                                      size: 16),
                                  label: const Text('Conectar por BLE'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                        ),
                        if (!connected && (_bleScanning || connecting))
                          _buildBleDiscoveredBanksList(),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBleDiscoveredBanksList() {
    final transport = P2PService().bleTransport;

    return ValueListenableBuilder<List<BleBankDevice>>(
      valueListenable: transport.discoveredBanksNotifier,
      builder: (context, banks, _) {
        if (banks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Buscando bancos BLE activos...',
              style: TextStyle(color: kTextSecondary, fontSize: 12),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bancos disponibles',
                style: TextStyle(
                  color: kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              ...banks.map((bank) {
                final selectedBank =
                    transport.connectedDeviceNameNotifier.value == bank.name;
                final isConnecting = selectedBank &&
                    transport.connectionStatusNotifier.value
                        .startsWith('Conectando');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isConnecting
                        ? null
                        : () {
                            SoundService.playClick();
                            _connectToBleBank(bank);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue
                            .withValues(alpha: isConnecting ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue
                              .withValues(alpha: isConnecting ? 0.65 : 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isConnecting)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.blue,
                              ),
                            )
                          else
                            const Icon(
                              Icons.account_balance_rounded,
                              color: Colors.blue,
                              size: 20,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bank.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: kTextPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  isConnecting
                                      ? 'Conectando, espera un momento...'
                                      : '${bank.proximityLabel} - ${bank.rssi} dBm',
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
                          if (!isConnecting)
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: kTextSecondary,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _compact(double val) {
    return formatMoney(val);
  }
}

class _PremiumCreditCard extends StatefulWidget {
  final double balance;
  final String name;
  final Color color;
  final int colorId;
  final List<double> history;
  final bool isBank;
  final CardTier? tier;

  const _PremiumCreditCard({
    required this.balance,
    required this.name,
    required this.color,
    required this.colorId,
    required this.history,
    required this.isBank,
    this.tier,
  });

  @override
  State<_PremiumCreditCard> createState() => _PremiumCreditCardState();
}

class _PremiumCreditCardState extends State<_PremiumCreditCard> {
  static const double _tiltFactor = 24.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double get balance => widget.balance;
  String get name => widget.name;
  Color get color => widget.color;
  int get colorId => widget.colorId;
  List<double> get history => widget.history;
  bool get isBank => widget.isBank;

  @override
  void initState() {
    super.initState();
    try {
      _gyroSub = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen((event) {
        if (!mounted) return;
        setState(() {
          _gyroX = (event.y).clamp(-0.8, 0.8);
          _gyroY = (-event.x).clamp(-0.8, 0.8);
        });
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cardHeight =
          ((constraints.maxWidth - 32) / 1.586).clamp(0.0, 240.0);

      final nameLower = widget.name.toLowerCase().trim();
      final Widget cardContent;
      if (nameLower == 'kevin' || nameLower == 'meibi') {
        cardContent = _buildVipBlackCard(cardHeight: cardHeight);
      } else {
        final wallet = context.read<WalletController>();
        final tier = widget.tier ?? wallet.currentTier;
        final styles = _getStyles(tier, color);

        cardContent = switch (tier) {
          CardTier.standard => _buildStandardCard(styles,
              cardHeight: cardHeight),
          CardTier.gold => _buildGoldCard(styles, cardHeight: cardHeight),
          CardTier.platinum => _buildPlatinumCard(styles,
              cardHeight: cardHeight),
          CardTier.black => _buildBlackCard(styles, cardHeight: cardHeight),
        };
      }

      return Transform(
        alignment: FractionalOffset.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_gyroY / _tiltFactor)
          ..rotateY(_gyroX / _tiltFactor),
        child: _ShimmerCard(child: cardContent),
      );
    });
  }

  Widget _buildStandardCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: styles.gradient,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
              color: styles.accent.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 8),
              spreadRadius: 0),
          BoxShadow(
              color: styles.accent.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
              right: -30,
              top: -30,
              child: Icon(Icons.circle, size: 200, color: Colors.white10)),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: cardHeight * 0.5,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.credit_card_rounded,
                        color: Colors.white70, size: 30),
                    Text(styles.tierName,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 4,
                          fontFamily: 'Courier')),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('JUGADOR',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 8)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('SALDO',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 8)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OdometerWidget(
                                  value: balance,
                                  color: Colors.white,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                              const SizedBox(width: 8),
                              _buildCardNetworkLogo(isVisa: true),
                            ],
                          ),
                        ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldCard(_CardStyles styles, {required double cardHeight}) {
    const goldLight = Color(0xFFFCF6BA);
    const goldDeep = Color(0xFFBF953F);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: styles.gradient,
        border: Border.all(
          color: goldLight.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
              color: goldDeep.withValues(alpha: 0.25),
              blurRadius: 14,
              spreadRadius: 0,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: goldLight.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Center(
              child: Opacity(
                  opacity: 0.1,
                  child:
                      Icon(Icons.stars_rounded, size: 200, color: goldLight))),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: cardHeight * 0.5,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16)),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Text(styles.tierName,
                        style: TextStyle(
                            color: goldLight.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFF3E2723),
                          fontSize: 18,
                          letterSpacing: 4,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('GOLD MEMBER',
                                style: TextStyle(
                                    color: Color(0xFF5D4037),
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFF3E2723),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('SALDO DISPONIBLE',
                              style: TextStyle(
                                  color: Color(0xFF5D4037),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OdometerWidget(
                                  value: balance,
                                  color: const Color(0xFF3E2723),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF3E2723))),
                              const SizedBox(width: 8),
                              _buildCardNetworkLogo(isVisa: false),
                            ],
                          ),
                        ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatinumCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: styles.gradient,
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(
        children: [
          ...List.generate(
              15,
              (index) => Positioned(
                    left: index * 40.0,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child:
                        Container(color: Colors.white.withValues(alpha: 0.03)),
                  )),
          // Watermark effect
          Positioned(
            right: -20,
            bottom: 40,
            child: Transform.rotate(
              angle: -0.2,
              child: Opacity(
                opacity: 0.05,
                child: Text(
                  'PLATINUM\nPRESTIGE',
                  style: TextStyle(
                    color: const Color(0xFF102A43),
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    height: 0.8,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEmvChipDesign(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.wifi_rounded,
                            color: Color(0xFF486581), size: 24),
                        Text(styles.tierName,
                            style: const TextStyle(
                                color: Color(0xFF486581),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.5)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFF102A43),
                          fontSize: 22,
                          letterSpacing: 4.5,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PLATINUM CARDHOLDER',
                                style: TextStyle(
                                    color: Color(0xFF486581),
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFF102A43),
                                    fontSize: 16,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('BALANCE DISPONIBLE',
                            style: TextStyle(
                                color: Color(0xFF486581),
                                fontSize: 7,
                                fontWeight: FontWeight.w900)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OdometerWidget(
                                value: balance,
                                color: const Color(0xFF102A43),
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF102A43))),
                            const SizedBox(width: 8),
                            _buildCardNetworkLogo(isVisa: true),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlackCard(_CardStyles styles, {required double cardHeight}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black,
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 5)
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CarbonFiberPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 32),
                    Text(styles.tierName,
                        style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4)),
                  ],
                ),
                const Spacer(),
                _buildEmvChipDesign(isBlack: true),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      isBank ? 'BANCO CENTRAL' : _generateCardNumber(name),
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 20,
                          letterSpacing: 5,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OdometerWidget(
                            value: balance,
                            color: const Color(0xFFD4AF37),
                            style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFD4AF37))),
                        const SizedBox(width: 8),
                        _buildCardNetworkLogo(isVisa: false),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_getRandomQuote(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: const Color(0xFFD4AF37)
                            .withValues(alpha: 0.6),
                        fontSize: 9,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmvChipDesign({bool isBlack = false}) {
    return Container(
      width: 45,
      height: 35,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: isBlack
                ? [Colors.grey.shade800, Colors.grey.shade600]
                : [Colors.amber.shade200, Colors.amber.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isBlack ? Colors.white24 : Colors.amber.shade700, width: 1),
      ),
      child: Stack(
        children: [
          Center(child: Container(width: 45, height: 1, color: Colors.black12)),
          Center(child: Container(width: 1, height: 35, color: Colors.black12)),
        ],
      ),
    );
  }

  Widget _buildCardNetworkLogo({required bool isVisa}) {
    if (isVisa) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('VISA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              )),
          Container(width: 30, height: 2, color: Colors.amber),
        ],
      );
    } else {
      return SizedBox(
        width: 40,
        height: 25,
        child: Stack(
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  shape: BoxShape.circle),
            ),
            Positioned(
              left: 12,
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.8),
                    shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildVipBlackCard({required double cardHeight}) {
    const goldDeep = Color(0xFFBF953F);
    const goldLight = Color(0xFFFCF6BA);
    const goldMid = Color(0xFFD4AF37);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: cardHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: goldMid, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: goldMid.withValues(alpha: 0.4),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: goldDeep.withValues(alpha: 0.2),
              blurRadius: 48,
              spreadRadius: -4),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
              right: -60,
              top: -60,
              child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        goldMid.withValues(alpha: 0.15),
                        Colors.transparent
                      ])))),
          Positioned(
              left: -40,
              bottom: -40,
              child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        goldDeep.withValues(alpha: 0.2),
                        Colors.transparent
                      ])))),
          Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MONOPOLY BANK',
                              style: TextStyle(
                                  color: goldLight,
                                  fontSize: 9,
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w800)),
                          const Text('VIP BLACK EDITION',
                              style: TextStyle(
                                  color: goldMid,
                                  fontSize: 8,
                                  letterSpacing: 2.5,
                                  fontWeight: FontWeight.w700)),
                        ]),
                    Icon(Icons.diamond_rounded, color: goldLight, size: 30),
                  ],
                ),
                const Spacer(),
                _buildEmvChipDesign(),
                const SizedBox(height: 12),
                Text(_generateCardNumber(name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Courier',
                        fontSize: 18,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PLATINUM CARDHOLDER',
                                style: TextStyle(color: goldDeep, fontSize: 7)),
                            Text(name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OdometerWidget(
                            value: balance,
                            color: goldLight,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: goldLight)),
                        const SizedBox(width: 8),
                        _buildCardNetworkLogo(isVisa: true),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _CardStyles _getStyles(CardTier tier, Color playerColor) {
    switch (tier) {
      case CardTier.standard:
        return _CardStyles(
          gradient: LinearGradient(
            colors: [
              playerColor,
              Color.lerp(playerColor, Colors.black, 0.4)!,
              Color.lerp(playerColor, Colors.black, 0.7)!
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'CLASSIC EDITION',
        );
      case CardTier.gold:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFBF953F),
              Color(0xFFFCF6BA),
              Color(0xFFB38728),
              Color(0xFFFBF5B7),
              Color(0xFFFBF5B7)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: const Color(0xFF2D2410),
          tierName: 'GOLD MEMBERSHIP',
        );
      case CardTier.platinum:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD), Color(0xFF757575)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.white,
          tierName: 'PLATINUM PRESTIGE',
        );
      case CardTier.black:
        return _CardStyles(
          gradient: const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accent: Colors.blueAccent,
          tierName: 'ULTIMATE BLACK',
        );
    }
  }

  String _generateCardNumber(String source) {
    if (source.isEmpty) source = "JUGADOR";
    // Usar el nombre como semilla para Random
    final seed = source
        .split('')
        .fold<int>(0, (prev, char) => prev + char.codeUnitAt(0));
    final rand = Random(seed);

    String part() => (rand.nextInt(9000) + 1000).toString().padLeft(4, '0');
    return "${part()} ${part()} ${part()} ${part()}";
  }

  String _getRandomQuote() {
    final quotes = [
      "Tu sueldo es mi propina.",
      "Demasiado rico para tener gusto.",
      "Mi única Bill es Gates.",
      "Compré el banco para no esperar.",
      "No hablo idioma 'descuento'.",
      "Más burbujas que tu cuenta.",
      "El caviar es mi snack.",
      "Oro para mis lentes.",
    ];
    return quotes[name.length % quotes.length];
  }
}

class _CardStyles {
  final LinearGradient gradient;
  final Color accent;
  final String tierName;
  _CardStyles(
      {required this.gradient, required this.accent, required this.tierName});
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: kBgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kTextSecondary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedPlayerTile extends StatelessWidget {
  final String name;
  final String deviceName;
  final String transport;
  final String detail;
  final Color color;
  final IconData icon;

  const _ConnectedPlayerTile({
    required this.name,
    required this.deviceName,
    required this.transport,
    required this.detail,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (deviceName.trim().isNotEmpty)
                  Text(
                    deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kTextSecondary.withValues(alpha: 0.62),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                Text(
                  '$transport - $detail',
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
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarbonFiberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double i = -size.height; i < size.width; i += 10) {
      canvas.drawLine(
          Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShimmerCard extends StatefulWidget {
  final Widget child;
  const _ShimmerCard({required this.child});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final shimmerPosition = _ctrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + shimmerPosition * 2, -1),
              end: Alignment(shimmerPosition * 2, 0.5),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.06),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}
