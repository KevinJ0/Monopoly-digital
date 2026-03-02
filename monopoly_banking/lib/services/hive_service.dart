import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:monopoly_banking/models/session_model.dart';
import 'package:monopoly_banking/models/transaction_model.dart';

class HiveService {
  static const _keyAlias = 'monopoly_hive_key';
  static const _sessionBox = 'session';
  static const _txBox = 'transactions';

  static final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static Future<void> init() async {
    await Hive.initFlutter();

    Hive.registerAdapter(SessionModelAdapter());
    Hive.registerAdapter(TransactionModelAdapter());

    final encryptionKey = await _getOrCreateKey();

    await Hive.openBox<SessionModel>(
      _sessionBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<TransactionModel>(
      _txBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Future<Uint8List> _getOrCreateKey() async {
    final stored = await _secureStorage.read(key: _keyAlias);
    if (stored != null) {
      return Uint8List.fromList(base64Decode(stored));
    }
    final key = Hive.generateSecureKey();
    await _secureStorage.write(
      key: _keyAlias,
      value: base64Encode(key),
    );
    return Uint8List.fromList(key);
  }

  static Box<SessionModel> get sessionBox => Hive.box<SessionModel>(_sessionBox);
  static Box<TransactionModel> get txBox => Hive.box<TransactionModel>(_txBox);
}
