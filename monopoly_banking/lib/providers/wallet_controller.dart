import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/models/session_model.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/voz_service.dart';
import 'package:monopoly_banking/services/biometria_service.dart';
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
  final StreamController<TxType> _txEvent = StreamController.broadcast();
  final StreamController<CardTier> _tierStream = StreamController.broadcast();

  final AudioPlayer _audioPlayer = AudioPlayer();

  List<TransactionModel>? _cachedHistory;

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

  Future<void> addFunds(double amount, {bool isPassGo = false}) async {
    final session = _session;
    if (session == null) return;

    session.balance += amount;
    session.txCount += 1;
    session.totalVolume += amount;

    if (isPassGo) {
      session.passGoCount += 1;

      if (session.vaultInvestedAmount > 0 &&
          session.vaultCurrentPasses < session.vaultTargetPasses) {
        session.vaultCurrentPasses += 1;

        final double rate;
        switch (session.vaultTargetPasses) {
          case 1:
            rate = 0.05;
            break;
          case 2:
            rate = 0.07;
            break;
          case 3:
            rate = 0.10;
            break;
          case 4:
            rate = 0.12;
            break;
          case 5:
            rate = 0.15;
            break;
          default:
            rate = 0.05;
        }

        final generated = session.vaultInvestedAmount * rate;
        session.vaultGeneratedAmount += generated;

        final msg = session.vaultCurrentPasses >= session.vaultTargetPasses
            ? "Inversión completada. Ganancia total: ${formatMoney(session.vaultGeneratedAmount)} pesos."
            : "Intereses de inversión generados: ${formatMoney(generated)} pesos. Pase ${session.vaultCurrentPasses} de ${session.vaultTargetPasses}.";

        VozService().hablar(msg);
      }
    }

    _recordHistory(session);
    syncTierWithBalance();
    await session.save();

    _stats.record(amount, isPassGo: isPassGo);
    rawBalance.value = session.balance;
    vaultInvestedAmount.value = session.vaultInvestedAmount;
    vaultGeneratedAmount.value = session.vaultGeneratedAmount;
    vaultCurrentPasses.value = session.vaultCurrentPasses;
    vaultTargetPasses.value = session.vaultTargetPasses;
    _txEvent.add(isPassGo ? TxType.passGo : TxType.received);

    if (amount >= 2000) {
      _txEvent.add(TxType.largeTransfer);
      VozService().hablar("Felicidades por su ingreso de capital.");
    }

    // Feedback
    try {
      _audioPlayer.play(AssetSource('sounds/cash.wav'));
    } catch (_) {}

    if (isPassGo) {
      HapticFeedback.vibrate(); // Impacto fuerte para GO
    } else {
      HapticFeedback.mediumImpact();
    }

    _persistTx(
      type: isPassGo ? 'passGo' : 'received',
      amount: amount,
      balanceAfter: session.balance,
    );

    notifyListeners();
  }

  Future<bool> subtractFunds(
    double amount, {
    String? counterpartyId,
  }) async {
    final session = _session;
    if (session == null) return false;

    if (session.balance < amount) return false;

    if (amount >= 5000) {
      final auth = await BiometriaService().autenticar(
          "Autorice la transferencia de alto valor por ${formatMoney(amount)}");
      if (!auth) return false;
    }

    session.balance -= amount;
    session.txCount += 1;
    session.totalVolume += amount;

    _recordHistory(session);
    await session.save();

    _stats.record(amount);
    rawBalance.value = session.balance;
    _txEvent.add(TxType.sent);

    // Feedback
    try {
      _audioPlayer.play(AssetSource('sounds/click.wav'));
    } catch (_) {}

    if (amount >= 2000) {
      VozService().hablar("Transferencia procesada, señor.");
    }

    HapticFeedback.lightImpact();

    _persistTx(
      type: 'sent',
      amount: amount,
      balanceAfter: session.balance,
      counterpartyId: counterpartyId,
    );

    if (session.balance == 0) {
      await _declareBankruptcy(session);
    }

    notifyListeners();
    return true;
  }

  Future<void> investInVault(double amount, int passes) async {
    final session = _session;
    if (session == null || session.balance < amount) return;

    session.balance -= amount;
    session.vaultInvestedAmount += amount;
    session.vaultTargetPasses = passes;
    session.vaultCurrentPasses = 0;
    session.vaultGeneratedAmount = 0.0;

    _recordHistory(session);
    await session.save();

    _updateVaultNotifiers(session);
    VozService().hablar("Capital invertido a $passes pases por GO.");
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  Future<void> withdrawVault() async {
    final session = _session;
    if (session == null || session.vaultInvestedAmount <= 0) return;

    final isEarly = session.vaultCurrentPasses < session.vaultTargetPasses;
    double amountToReturn = 0;

    if (isEarly) {
      // 20% penalty on invested amount, lose generated interests
      amountToReturn = session.vaultInvestedAmount * 0.80;
      VozService().hablar(
          "Retiro anticipado con penalización. Recuperado ${formatMoney(amountToReturn)} pesos.");
    } else {
      // Full amount + generated interests
      amountToReturn =
          session.vaultInvestedAmount + session.vaultGeneratedAmount;
      VozService().hablar(
          "Inversión retirada con éxito. Capital más intereses: ${formatMoney(amountToReturn)} pesos.");
    }

    session.balance += amountToReturn;
    session.vaultInvestedAmount = 0.0;
    session.vaultGeneratedAmount = 0.0;
    session.vaultCurrentPasses = 0;
    session.vaultTargetPasses = 0;

    _recordHistory(session);
    await session.save();

    _updateVaultNotifiers(session);
    HapticFeedback.mediumImpact();
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
    int newTierIdx = currentTierIdx;

    if (session.balance >= 15000) {
      newTierIdx = 3; // Black
    } else if (session.balance >= 8000) {
      newTierIdx = 2; // Platinum
    } else if (session.balance >= 4000) {
      newTierIdx = 1; // Gold
    }

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

  Future<void> _declareBankruptcy(SessionModel session) async {
    session.isBankrupt = true;
    await session.save();
    bankruptNotifier.value = true;
    _txEvent.add(TxType.sent);
    await P2PService().shutdown();
    notifyListeners();
  }

  void _persistTx({
    required String type,
    required double amount,
    required double balanceAfter,
    String? counterpartyId,
  }) {
    final tx = TransactionModel(
      id: _uuid.v4(),
      type: type,
      amount: amount,
      timestamp: DateTime.now(),
      counterpartyId: counterpartyId,
      balanceAfter: balanceAfter,
    );
    HiveService.txBox.put(tx.id, tx);
    _cachedHistory?.insert(0, tx);
  }

  List<TransactionModel> get history {
    _cachedHistory ??= HiveService.txBox.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _cachedHistory!;
  }

  @override
  void dispose() {
    _txEvent.close();
    _tierStream.close();
    rawBalance.dispose();
    bankruptNotifier.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
