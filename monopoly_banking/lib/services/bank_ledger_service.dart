import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/models/transaction_model.dart';
import 'package:monopoly_banking/services/hive_service.dart';

class BankLedgerException implements Exception {
  final String message;

  const BankLedgerException(this.message);

  @override
  String toString() => message;
}

class BankPlayerAccount {
  final String playerId;
  final String deviceInstallationId;
  final double balance;
  final bool bankrupt;
  final double investedAmount;
  final double generatedAmount;
  final int targetPasses;
  final int currentPasses;

  const BankPlayerAccount({
    required this.playerId,
    required this.balance,
    this.deviceInstallationId = '',
    this.bankrupt = false,
    this.investedAmount = 0,
    this.generatedAmount = 0,
    this.targetPasses = 0,
    this.currentPasses = 0,
  });

  factory BankPlayerAccount.fromMap(
      String playerId, Map<dynamic, dynamic> map) {
    return BankPlayerAccount(
      playerId: playerId,
      deviceInstallationId:
          (map['deviceInstallationId'] as String?)?.trim() ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      bankrupt: map['bankrupt'] as bool? ?? false,
      investedAmount: (map['investedAmount'] as num?)?.toDouble() ?? 0,
      generatedAmount: (map['generatedAmount'] as num?)?.toDouble() ?? 0,
      targetPasses: (map['targetPasses'] as num?)?.toInt() ?? 0,
      currentPasses: (map['currentPasses'] as num?)?.toInt() ?? 0,
    );
  }

  BankPlayerAccount copyWith({
    double? balance,
    String? deviceInstallationId,
    bool? bankrupt,
    double? investedAmount,
    double? generatedAmount,
    int? targetPasses,
    int? currentPasses,
  }) {
    return BankPlayerAccount(
      playerId: playerId,
      deviceInstallationId: deviceInstallationId ?? this.deviceInstallationId,
      balance: balance ?? this.balance,
      bankrupt: bankrupt ?? this.bankrupt,
      investedAmount: investedAmount ?? this.investedAmount,
      generatedAmount: generatedAmount ?? this.generatedAmount,
      targetPasses: targetPasses ?? this.targetPasses,
      currentPasses: currentPasses ?? this.currentPasses,
    );
  }

  Map<String, dynamic> toMap() => {
        'balance': balance,
        'deviceInstallationId': deviceInstallationId,
        'bankrupt': bankrupt,
        'investedAmount': investedAmount,
        'generatedAmount': generatedAmount,
        'targetPasses': targetPasses,
        'currentPasses': currentPasses,
      };

  Map<String, dynamic> toClientState() => {
        'balance': balance,
        'isBankrupt': bankrupt,
        'vaultInvestedAmount': investedAmount,
        'vaultGeneratedAmount': generatedAmount,
        'vaultTargetPasses': targetPasses,
        'vaultCurrentPasses': currentPasses,
      };
}

class BankLedgerResult {
  final BankPlayerAccount account;
  final String transactionId;
  final String eventType;
  final double amount;
  final double generatedInterest;
  final String bankSessionId;

  const BankLedgerResult({
    required this.account,
    required this.transactionId,
    required this.eventType,
    required this.amount,
    required this.bankSessionId,
    this.generatedInterest = 0,
  });

  Map<String, dynamic> toClientPayload() => {
        'type': 'bank_state',
        'targetPlayerId': account.playerId,
        'bankTxId': transactionId,
        'eventType': eventType,
        'amount': amount,
        'generatedInterest': generatedInterest,
        'bankSessionId': bankSessionId,
        ...account.toClientState(),
      };
}

class BankLedgerService {
  static final BankLedgerService _instance = BankLedgerService._();
  factory BankLedgerService() => _instance;
  BankLedgerService._();

  final ValueNotifier<int> statsRevision = ValueNotifier<int>(0);
  String? _cachedBankSessionId;

  static const _accountsKey = 'bank_ledger_accounts_v1';
  static const _transactionsKey = 'bank_ledger_transactions_v1';
  static const _bankSessionIdKey = 'bank_ledger_session_id_v1';
  static const _bannedDevicesKey = 'bank_ledger_banned_devices_v1';

  int _transactionCounter = 0;

  Map<String, dynamic> _readAccounts() {
    final stored = HiveService.settingsBox.get(_accountsKey);
    if (stored is! Map) return <String, dynamic>{};
    return stored.map((key, value) => MapEntry(key.toString(), value));
  }

  List<Map<String, dynamic>> _readTransactions() {
    final stored = HiveService.settingsBox.get(_transactionsKey);
    if (stored is! List) return <Map<String, dynamic>>[];
    return stored.whereType<Map>().map((entry) {
      return entry.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  BankPlayerAccount? accountFor(String playerId) {
    final raw = _readAccounts()[playerId];
    if (raw is! Map) return null;
    return BankPlayerAccount.fromMap(playerId, raw);
  }

  List<Map<String, dynamic>> get transactionHistory => _readTransactions();

  Future<BankLedgerResult> ensurePlayer(
    String playerId,
    double initialBalance, {
    String? deviceInstallationId,
  }) async {
    _validatePlayerId(playerId);
    final existing = accountFor(playerId);
    final account = existing?.copyWith(
          deviceInstallationId: deviceInstallationId,
        ) ??
        BankPlayerAccount(
          playerId: playerId,
          balance: initialBalance,
          deviceInstallationId: deviceInstallationId ?? '',
        );
    await _saveAccount(account);
    return _record(
      account: account,
      type: existing == null ? 'handshake_initial' : 'handshake_reconnect',
      amount: 0,
    );
  }

  Future<BankLedgerResult> credit(
    String playerId,
    double amount, {
    String type = 'payment',
    String? counterpartyId,
  }) async {
    _validateAmount(amount);
    final current = _requireAccount(playerId);
    final account = current.copyWith(balance: current.balance + amount);
    await _saveAccount(account);
    return _record(
      account: account,
      type: type,
      amount: amount,
      counterpartyId: counterpartyId,
    );
  }

  Future<BankLedgerResult> debit(
    String playerId,
    double amount, {
    String type = 'charge',
    String? counterpartyId,
  }) async {
    _validateAmount(amount);
    final current = _requireAccount(playerId);
    if (current.balance < amount) {
      throw const BankLedgerException('Saldo insuficiente en el banco.');
    }
    final account = current.copyWith(balance: current.balance - amount);
    await _saveAccount(account);
    return _record(
      account: account,
      type: type,
      amount: amount,
      counterpartyId: counterpartyId,
    );
  }

  Future<BankLedgerResult> passGo(String playerId) async {
    final current = _requireAccount(playerId);
    var generatedInterest = 0.0;
    var generated = current.generatedAmount;
    var currentPasses = current.currentPasses;

    if (current.investedAmount > 0 && currentPasses < current.targetPasses) {
      currentPasses += 1;
      generatedInterest =
          current.investedAmount * _rateFor(current.targetPasses);
      generated += generatedInterest;
    }

    final account = current.copyWith(
      balance: current.balance + kPassGoAmount,
      generatedAmount: generated,
      currentPasses: currentPasses,
    );
    await _saveAccount(account);
    return _record(
      account: account,
      type: 'passGo',
      amount: kPassGoAmount,
      metadata: {'generatedInterest': generatedInterest},
      generatedInterest: generatedInterest,
    );
  }

  Future<BankLedgerResult> invest(
    String playerId,
    double amount,
    int passes,
  ) async {
    _validateAmount(amount);
    if (passes < 1 || passes > 5) {
      throw const BankLedgerException('La inversión debe durar de 1 a 5 GO.');
    }
    final current = _requireAccount(playerId);
    if (current.investedAmount > 0) {
      throw const BankLedgerException('Ya existe una inversión activa.');
    }
    if (current.balance < amount) {
      throw const BankLedgerException('Saldo insuficiente en el banco.');
    }

    final account = current.copyWith(
      balance: current.balance - amount,
      investedAmount: amount,
      generatedAmount: 0,
      targetPasses: passes,
      currentPasses: 0,
    );
    await _saveAccount(account);
    return _record(
      account: account,
      type: 'investment_opened',
      amount: amount,
      metadata: {'targetPasses': passes},
    );
  }

  Future<BankLedgerResult> withdrawInvestment(String playerId) async {
    final current = _requireAccount(playerId);
    if (current.investedAmount <= 0) {
      throw const BankLedgerException('No existe una inversión activa.');
    }

    if (current.currentPasses < current.targetPasses) {
      throw const BankLedgerException(
        'La inversión aún no ha cumplido el plazo. Debes completar los pases por GO antes de retirar.',
      );
    }

    final returnedAmount = current.investedAmount + current.generatedAmount;
    final account = current.copyWith(
      balance: current.balance + returnedAmount,
      investedAmount: 0,
      generatedAmount: 0,
      targetPasses: 0,
      currentPasses: 0,
    );
    await _saveAccount(account);
    return _record(
      account: account,
      type: 'investment_completed',
      amount: returnedAmount,
    );
  }

  Future<BankLedgerResult> markBankrupt(
    String playerId, {
    required double attemptedCharge,
    required String deviceInstallationId,
  }) async {
    final current = _requireAccount(playerId);
    final account = current.copyWith(
      balance: 0,
      bankrupt: true,
      deviceInstallationId: deviceInstallationId,
      investedAmount: 0,
      generatedAmount: 0,
      targetPasses: 0,
      currentPasses: 0,
    );
    await _saveAccount(account);
    await banDevice(deviceInstallationId, playerId);
    return _record(
      account: account,
      type: 'bankruptcy',
      amount: attemptedCharge,
      counterpartyId: 'Banco',
      metadata: {'attemptedCharge': attemptedCharge},
    );
  }

  bool isDeviceBanned(String deviceInstallationId) {
    if (deviceInstallationId.isEmpty) return false;
    final raw = HiveService.settingsBox.get(_bannedDevicesKey);
    if (raw is! Map) return false;
    final entry = raw[deviceInstallationId];
    if (entry is! Map) return false;
    return entry['sessionId'] == currentBankSessionId;
  }

  Future<void> banDevice(
    String deviceInstallationId,
    String playerId,
  ) async {
    if (deviceInstallationId.isEmpty) return;
    final raw = HiveService.settingsBox.get(_bannedDevicesKey);
    final banned = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    banned[deviceInstallationId] = {
      'sessionId': currentBankSessionId,
      'playerId': playerId,
      'bannedAt': DateTime.now().toIso8601String(),
    };
    await HiveService.settingsBox.put(_bannedDevicesKey, banned);
  }

  Future<void> closeBankSession() async {
    await HiveService.settingsBox.delete(_accountsKey);
    await HiveService.settingsBox.delete(_transactionsKey);
    await HiveService.settingsBox.delete(_bannedDevicesKey);
    await HiveService.settingsBox.delete(_bankSessionIdKey);
    _cachedBankSessionId = null;
  }

  String get currentBankSessionId {
    final cached = _cachedBankSessionId;
    if (cached != null && cached.isNotEmpty) return cached;
    final stored = HiveService.settingsBox.get(_bankSessionIdKey) as String?;
    if (stored != null && stored.isNotEmpty) {
      _cachedBankSessionId = stored;
      return stored;
    }
    final generated =
        'bank-${DateTime.now().microsecondsSinceEpoch}-${_transactionCounter++}';
    _cachedBankSessionId = generated;
    unawaited(HiveService.settingsBox.put(_bankSessionIdKey, generated));
    return generated;
  }

  Future<void> _saveAccount(BankPlayerAccount account) async {
    final accounts = _readAccounts();
    accounts[account.playerId] = account.toMap();
    await HiveService.settingsBox.put(_accountsKey, accounts);
  }

  Future<BankLedgerResult> _record({
    required BankPlayerAccount account,
    required String type,
    required double amount,
    String? counterpartyId,
    Map<String, dynamic>? metadata,
    double generatedInterest = 0,
  }) async {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_transactionCounter++}';
    final transactions = _readTransactions();
    transactions.insert(0, {
      'id': id,
      'playerId': account.playerId,
      'type': type,
      'amount': amount,
      'balanceAfter': account.balance,
      'counterpartyId': counterpartyId,
      'timestamp': DateTime.now().toIso8601String(),
      'metadata': metadata ?? <String, dynamic>{},
    });
    await HiveService.settingsBox.put(_transactionsKey, transactions);
    await HiveService.txBox.put(
      id,
      TransactionModel(
        id: id,
        type: _bankHistoryType(type),
        amount: amount,
        timestamp: DateTime.now(),
        counterpartyId: counterpartyId ?? account.playerId,
        balanceAfter: account.balance,
      ),
    );
    await _recordBankStats(type: type, amount: amount);
    return BankLedgerResult(
      account: account,
      transactionId: id,
      eventType: type,
      amount: amount,
      bankSessionId: currentBankSessionId,
      generatedInterest: generatedInterest,
    );
  }

  Future<void> _recordBankStats({
    required String type,
    required double amount,
  }) async {
    if (type.startsWith('handshake_')) return;
    final session = HiveService.sessionBox.get('current');
    if (session == null || session.role != 'banco') return;

    session.totalVolume += amount.abs();
    session.txCount += 1;
    if (type == 'passGo') session.passGoCount += 1;
    await session.save();
    statsRevision.value += 1;
  }

  String _bankHistoryType(String type) {
    return switch (type) {
      'payment' => 'bank_payment_sent',
      'charge' => 'bank_charge_received',
      'passGo' => 'bank_pass_go_sent',
      'handshake_initial' => 'bank_player_joined',
      'handshake_reconnect' => 'bank_player_reconnected',
      'bankruptcy' => 'bank_bankruptcy',
      _ => 'bank_$type',
    };
  }

  BankPlayerAccount _requireAccount(String playerId) {
    _validatePlayerId(playerId);
    final account = accountFor(playerId);
    if (account == null) {
      throw const BankLedgerException('El jugador necesita un handshake.');
    }
    if (account.bankrupt) {
      throw const BankLedgerException(
        'El jugador está en bancarrota y no puede realizar operaciones.',
      );
    }
    return account;
  }

  void _validatePlayerId(String playerId) {
    if (playerId.trim().isEmpty) {
      throw const BankLedgerException('El jugador no tiene un nombre válido.');
    }
  }

  void _validateAmount(double amount) {
    if (!amount.isFinite || amount <= 0) {
      throw const BankLedgerException('El monto no es válido.');
    }
  }

  double _rateFor(int passes) {
    return switch (passes) {
      1 => 0.05,
      2 => 0.07,
      3 => 0.10,
      4 => 0.12,
      5 => 0.15,
      _ => 0,
    };
  }
}
