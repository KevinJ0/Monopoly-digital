import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/models/session_model.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/sound_service.dart';
import 'package:monopoly_banking/services/notification_service.dart';
import 'package:uuid/uuid.dart';

enum TxType { received, sent, passGo, largeTransfer }

enum CardTier { standard, gold, platinum, black }

class WalletController extends ChangeNotifier {
  final StatsProvider _stats;
  final _uuid = const Uuid();

  final ValueNotifier<double> rawBalance = ValueNotifier(0);
  final ValueNotifier<double> vaultInvestedAmount = ValueNotifier(0);
  final ValueNotifier<double> vaultGeneratedAmount = ValueNotifier(0);
  final ValueNotifier<int> vaultTargetPasses = ValueNotifier(0);
  final ValueNotifier<int> vaultCurrentPasses = ValueNotifier(0);
  final ValueNotifier<bool> bankruptNotifier = ValueNotifier(false);
  final ValueNotifier<int> balanceDecreaseShake = ValueNotifier(0);
  final StreamController<TxType> _txEvent = StreamController.broadcast();
  final StreamController<CardTier> _tierStream = StreamController.broadcast();

  final AudioPlayer _audioPlayer = AudioPlayer()
    ..setAudioContext(SoundService.effectsAudioContext);

  Stream<TxType> get txStream => _txEvent.stream;
  Stream<CardTier> get tierStream => _tierStream.stream;

  WalletController(this._stats);

  SessionModel? get _session => HiveService.sessionBox.get('current');

  double get balance => _session?.balance ?? 0;
  double get investedVault => _session?.vaultInvestedAmount ?? 0;
  double get generatedVault => _session?.vaultGeneratedAmount ?? 0;
  int get targetPassesVault => _session?.vaultTargetPasses ?? 0;
  int get currentPassesVault => _session?.vaultCurrentPasses ?? 0;
  bool get isBankrupt => _session?.isBankrupt ?? false;
  List<double> get historyData => _session?.balanceHistory ?? [];
  CardTier get maxTier => CardTier.values[_session?.maxTier ?? 0];
  CardTier get currentTier => _tierForBalance(balance);

  CardTier _tierForBalance(double value) {
    if (value >= 15000) return CardTier.black;
    if (value >= 8000) return CardTier.platinum;
    if (value >= 4000) return CardTier.gold;
    return CardTier.standard;
  }

  Future<void> applyBankState(Map<String, dynamic> payload) async {
    final session = _session;
    if (session == null || session.role == 'banco') {
      debugPrint('[┊] APPLY_BANK EARLY: session is null or bank');
      return;
    }

    final bankTxId = payload['bankTxId'] as String?;
    if (bankTxId != null && HiveService.txBox.containsKey(bankTxId)) {
      debugPrint('[┊] APPLY_BANK EARLY: bankTxId=$bankTxId already processed — syncing notifiers from session');
      if (session != null) {
        _updateVaultNotifiers(session);
      }
      notifyListeners();
      return;
    }
    debugPrint('[┊] APPLY_BANK PROCESSING: bankTxId=$bankTxId');

    final rawBalanceValue = payload['balance'] as num?;
    if (rawBalanceValue == null || !rawBalanceValue.isFinite) return;

    final eventType = (payload['eventType'] as String?) ?? 'bank_sync';
    final isHandshake = eventType == 'handshake_initial' || eventType == 'handshake_reconnect';
    debugPrint('[┊] APPLY_BANK eventType=$eventType isHandshake=$isHandshake isBankrupt=${payload['isBankrupt']} skipBankruptNotifier=${isHandshake ? 'YES' : 'NO'}');
    final previousBalance = session.balance;
    session.balance = rawBalanceValue.toDouble();
    session.vaultInvestedAmount =
        (payload['vaultInvestedAmount'] as num?)?.toDouble() ?? 0;
    session.vaultGeneratedAmount =
        (payload['vaultGeneratedAmount'] as num?)?.toDouble() ?? 0;
    session.vaultTargetPasses =
        (payload['vaultTargetPasses'] as num?)?.toInt() ?? 0;
    session.vaultCurrentPasses =
        (payload['vaultCurrentPasses'] as num?)?.toInt() ?? 0;
    session.isBankrupt = payload['isBankrupt'] as bool? ?? false;

    _recordHistory(session);
    await session.save();
    _updateVaultNotifiers(session);
    if (!isHandshake) {
      bankruptNotifier.value = session.isBankrupt;
    }
    syncTierWithBalance();

    final balanceDiff = (session.balance - previousBalance).abs();
    final rawAmount = (payload['amount'] as num?)?.toDouble();
    final amount = (rawAmount != null && rawAmount > 0)
        ? rawAmount
        : balanceDiff;

    if (amount > 0 && balanceDiff > 0) {
      final txId = bankTxId ?? 'local-${DateTime.now().microsecondsSinceEpoch}';
      if (!HiveService.txBox.containsKey(txId)) {
        _persistTx(
          id: txId,
          type: eventType == 'bank_sync'
              ? (session.balance > previousBalance
                  ? 'sync_credit'
                  : 'sync_debit')
              : eventType,
          amount: amount,
          balanceAfter: session.balance,
          counterpartyId: payload['counterpartyId'] as String?,
        );
      }
    }

    if (session.balance > previousBalance) {
      _stats.record(amount, isPassGo: eventType == 'passGo');
      _txEvent.add(eventType == 'passGo' ? TxType.passGo : TxType.received);
      if (eventType == 'passGo') {
        SoundService.playFanfare();
        HapticFeedback.vibrate();
        NotificationService().show('Pase por GO: +${formatMoney(amount)}',
            backgroundColor: kGold);
      } else {
        unawaited(_audioPlayer.play(AssetSource('sounds/cash.wav')));
        HapticFeedback.mediumImpact();
        NotificationService().show('Recibiste ${formatMoney(amount)}',
            backgroundColor: kGreen);
      }
    } else if (session.balance < previousBalance) {
      _stats.record(amount);
      _txEvent.add(TxType.sent);
      if (eventType == 'investment_opened') {
        NotificationService().show(
            'Inversión de ${formatMoney(amount)} iniciada',
            backgroundColor: kGold);
      } else {
        unawaited(_audioPlayer.play(AssetSource('sounds/click.wav')));
        HapticFeedback.lightImpact();
        final loss = previousBalance - session.balance;
        if (loss >= 500) {
          balanceDecreaseShake.value++;
          HapticFeedback.heavyImpact();
          SoundService.playSadTrombone();
        }
        NotificationService().show(
            'Transferiste ${formatMoney(amount)}',
            backgroundColor: kRed);
      }
    }

    notifyListeners();
  }

  void _updateVaultNotifiers(SessionModel session) {
    rawBalance.value = session.balance;
    vaultInvestedAmount.value = session.vaultInvestedAmount;
    vaultGeneratedAmount.value = session.vaultGeneratedAmount;
    vaultCurrentPasses.value = session.vaultCurrentPasses;
    vaultTargetPasses.value = session.vaultTargetPasses;
  }

  void syncTierWithBalance() {
    final session = _session;
    if (session == null || session.role == 'bank') return;

    int currentTierIdx = session.maxTier;
    final newTierIdx = _tierForBalance(session.balance).index;

    if (newTierIdx > currentTierIdx) {
      session.maxTier = newTierIdx;
      session.save(); // Persistir el logro
      _tierStream.add(CardTier.values[newTierIdx]);
      notifyListeners();
    }
  }

  void _recordHistory(SessionModel session) {
    session.balanceHistory.add(session.balance);
    if (session.balanceHistory.length > 20) {
      session.balanceHistory.removeAt(0);
    }
  }

  void _persistTx({
    String? id,
    required String type,
    required double amount,
    required double balanceAfter,
    String? counterpartyId,
  }) {
    final tx = TransactionModel(
      id: id ?? _uuid.v4(),
      type: type,
      amount: amount,
      timestamp: DateTime.now(),
      counterpartyId: counterpartyId,
      balanceAfter: balanceAfter,
    );
    HiveService.txBox.put(tx.id, tx);
  }

  List<TransactionModel> get history {
    return HiveService.txBox.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void refreshHistory() => notifyListeners();

  @override
  void dispose() {
    _txEvent.close();
    _tierStream.close();
    rawBalance.dispose();
    bankruptNotifier.dispose();
    balanceDecreaseShake.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
