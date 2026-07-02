import 'package:flutter/material.dart';
import 'package:monopoly_banking/models/session_model.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/services/hive_service.dart';
import 'package:monopoly_banking/services/bank_ledger_service.dart';
import 'package:monopoly_banking/services/p2p_service.dart';

class SessionProvider extends ChangeNotifier {
  static const _playerBankSessionKey = 'player_bank_session_id_v1';
  final StatsProvider _stats;
  final WalletController _wallet;

  String _role = 'cliente';
  String _avatarId = '';
  String _colorId = '0';
  String _name = '';
  bool _isHandshakeDone = false;
  bool _initialized = false;

  String get role => _role;
  String get avatarId => _avatarId;
  String get colorId => _colorId;
  String get name => _name;
  bool get isHandshakeDone => _isHandshakeDone;
  bool get isBank => _role == 'banco';
  bool get initialized => _initialized;

  Color get color {
    final index = int.tryParse(_colorId) ?? 0;
    if (index >= 0 && index < _colors.length) return _colors[index];
    return _colors[0];
  }

  static const _colors = [
    Color(0xFFE53935),
    Color(0xFF8E24AA),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFDD835),
    Color(0xFFFF7043),
    Color(0xFF00ACC1),
    Color(0xFFECEFF1),
  ];

  SessionProvider(this._stats, this._wallet);

  Future<void> restoreSession() async {
    final box = HiveService.sessionBox;
    final session = box.get('current');
    if (session == null) {
      _initialized = true;
      notifyListeners();
      return;
    }

    _role = session.role;
    _avatarId = session.avatarId;
    _colorId = session.colorId;
    _name = session.name ?? '';
    _isHandshakeDone = session.isHandshakeDone;

    _stats.restore(
      volume: session.totalVolume,
      count: session.txCount,
      passGo: session.passGoCount,
    );

    final double restoredBalance =
        session.role == 'banco' || session.isHandshakeDone
            ? session.balance
            : 0;
    _wallet.rawBalance.value = restoredBalance;
    _wallet.bankruptNotifier.value = session.isBankrupt;
    _wallet.syncTierWithBalance();

    if (session.isBankrupt) {
      await P2PService().shutdown();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> createSession({
    required String role,
    required String avatarId,
    required String colorId,
    required double initialBalance,
    String? name,
    bool isHandshakeDone = false,
  }) async {
    _role = role;
    _avatarId = avatarId;
    _colorId = colorId;
    _name = name ?? (role == 'banco' ? 'Banca Central' : '');
    _isHandshakeDone = isHandshakeDone;

    final session = SessionModel(
      role: role,
      balance: initialBalance,
      avatarId: avatarId,
      colorId: colorId,
      name: name,
      isHandshakeDone: isHandshakeDone,
    );

    await HiveService.sessionBox.put('current', session);
    _wallet.rawBalance.value = initialBalance;
    _wallet.syncTierWithBalance();
    _initialized = true;
    notifyListeners();
  }

  Future<void> clearSession() async {
    if (isBank) await BankLedgerService().closeBankSession();
    await HiveService.sessionBox.delete('current');
    await HiveService.txBox.clear();
    await HiveService.settingsBox.delete(_playerBankSessionKey);
    _role = '';
    _avatarId = '';
    _colorId = '0';
    _name = '';
    _isHandshakeDone = false;
    _wallet.rawBalance.value = 0;
    _wallet.bankruptNotifier.value = false;
    _stats.restore(volume: 0, count: 0, passGo: 0);
    notifyListeners();
  }

  Future<bool> adoptBankSession(String? bankSessionId) async {
    final incoming = bankSessionId?.trim();
    if (incoming == null || incoming.isEmpty || isBank) return false;
    final stored =
        HiveService.settingsBox.get(_playerBankSessionKey) as String?;
    if (stored == null || stored.isEmpty) {
      await HiveService.settingsBox.put(_playerBankSessionKey, incoming);
      return false;
    }
    if (stored == incoming) return false;

    final current = HiveService.sessionBox.get('current');
    final avatar = current?.avatarId ?? _avatarId;
    final color = current?.colorId ?? _colorId;
    final playerName = current?.name ?? _name;
    await HiveService.txBox.clear();
    _stats.restore(volume: 0, count: 0, passGo: 0);
    await createSession(
      role: 'cliente',
      avatarId: avatar,
      colorId: color,
      initialBalance: 0,
      name: playerName,
      isHandshakeDone: false,
    );
    _wallet.vaultInvestedAmount.value = 0;
    _wallet.vaultGeneratedAmount.value = 0;
    _wallet.vaultTargetPasses.value = 0;
    _wallet.vaultCurrentPasses.value = 0;
    _wallet.bankruptNotifier.value = false;
    await HiveService.settingsBox.put(_playerBankSessionKey, incoming);
    return true;
  }

  Future<void> applyHandshake(Map<String, dynamic> payload) async {
    if (_isHandshakeDone) return;

    final balance = (payload['balance'] as num).toDouble();
    final avatar = payload['avatarId'] as String;
    final color = payload['colorId'] as String;
    // Prefer existing name if available (already entered in RoleSelection),
    // otherwise fallback to any name sent in the handshake.
    final finalName = _name.isNotEmpty ? _name : (payload['name'] as String?);

    await createSession(
      role: 'cliente',
      avatarId: avatar,
      colorId: color,
      initialBalance: balance,
      name: finalName,
      isHandshakeDone: true,
    );
  }
}
