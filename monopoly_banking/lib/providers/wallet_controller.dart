import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:monopoly_banking/models/session_model.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/voz_service.dart';
import 'package:monopoly_banking/services/biometria_service.dart';
import 'package:uuid/uuid.dart';

enum TxType { received, sent, passGo, largeTransfer }

class WalletController extends ChangeNotifier {
  final StatsProvider _stats;
  final _uuid = const Uuid();

  final ValueNotifier<double> rawBalance = ValueNotifier(0);
  final ValueNotifier<double> vaultInvestedAmount = ValueNotifier(0);
  final ValueNotifier<double> vaultGeneratedAmount = ValueNotifier(0);
  final ValueNotifier<int> vaultTargetPasses = ValueNotifier(0);
  final ValueNotifier<int> vaultCurrentPasses = ValueNotifier(0);
  final StreamController<TxType> _txEvent = StreamController.broadcast();
  final ValueNotifier<bool> bankruptNotifier = ValueNotifier(false);

  final AudioPlayer _audioPlayer = AudioPlayer();

  Stream<TxType> get txStream => _txEvent.stream;

  WalletController(this._stats);

  SessionModel? get _session => HiveService.sessionBox.get('current');

  double get balance => _session?.balance ?? 0;
  double get investedVault => _session?.vaultInvestedAmount ?? 0;
  double get generatedVault => _session?.vaultGeneratedAmount ?? 0;
  int get targetPassesVault => _session?.vaultTargetPasses ?? 0;
  int get currentPassesVault => _session?.vaultCurrentPasses ?? 0;
  bool get isBankrupt => _session?.isBankrupt ?? false;
  List<double> get historyData => _session?.balanceHistory ?? [];

  Future<void> addFunds(double amount, {bool isPassGo = false}) async {
    final session = _session;
    if (session == null) return;

    session.balance += amount;
    session.txCount += 1;
    session.totalVolume += amount;

    if (isPassGo) {
      session.passGoCount += 1;

      if (session.vaultInvestedAmount > 0 && session.vaultCurrentPasses < session.vaultTargetPasses) {
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
            ? "Inversión completada. Ganancia total: ${session.vaultGeneratedAmount.round()} pesos."
            : "Intereses de inversión generados: ${generated.round()} pesos. Pase ${session.vaultCurrentPasses} de ${session.vaultTargetPasses}.";

        VozService().hablar(msg);
      }
    }

    _recordHistory(session);
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
      _audioPlayer.play(AssetSource('sounds/cash.mp3'));
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
      final auth = await BiometriaService().autenticar("Autorice la transferencia de alto valor por \$${amount.round()}");
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
      _audioPlayer.play(AssetSource('sounds/click.mp3'));
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
      VozService().hablar("Retiro anticipado con penalización. Recuperado ${amountToReturn.round()} pesos.");
    } else {
      // Full amount + generated interests
      amountToReturn = session.vaultInvestedAmount + session.vaultGeneratedAmount;
      VozService().hablar("Inversión retirada con éxito. Capital más intereses: ${amountToReturn.round()} pesos.");
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
  }

  List<TransactionModel> get history => HiveService.txBox.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  @override
  void dispose() {
    _txEvent.close();
    rawBalance.dispose();
    bankruptNotifier.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
