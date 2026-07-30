import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:money_manager/models/session_model.dart';
import 'package:money_manager/models/transaction_model.dart';

class HiveService {
  static const _keyAlias = 'money_manager_hive_key';
  static const _sessionBox = 'session';
  static const _txBox = 'transactions';
  static const _settingsBox = 'settings';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  static Future<void> init() async {
    if (!kIsWeb && Platform.isWindows) {
      await _initWindows();
    } else {
      await Hive.initFlutter();
    }

    if (!Hive.isAdapterRegistered(SessionModelAdapter().typeId)) {
      Hive.registerAdapter(SessionModelAdapter());
    }
    if (!Hive.isAdapterRegistered(TransactionModelAdapter().typeId)) {
      Hive.registerAdapter(TransactionModelAdapter());
    }

    final encryptionKey = await _getOrCreateKey();

    try {
      await Hive.openBox<SessionModel>(
        _sessionBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );

      await Hive.openBox<TransactionModel>(
        _txBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox(
        _settingsBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
    } catch (e) {
      await Hive.deleteBoxFromDisk(_sessionBox);
      await Hive.deleteBoxFromDisk(_txBox);
      await Hive.deleteBoxFromDisk(_settingsBox);

      await Hive.openBox<SessionModel>(
        _sessionBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox<TransactionModel>(
        _txBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox(
        _settingsBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
    }
  }

  static Future<void> _initWindows() async {
    try {
      final appDir = await _getDesktopPath();
      Hive.init(appDir.path);
    } catch (_) {
      final tempDir = Directory.systemTemp.createTempSync('money_manager_');
      Hive.init(tempDir.path);
    }
  }

  static Future<Directory> _getDesktopPath() async {
    final appDir = Directory(
      '${Platform.environment['APPDATA']}\\money_manager_banking',
    );
    if (!appDir.existsSync()) {
      appDir.createSync(recursive: true);
    }
    return appDir;
  }

  static Future<Uint8List> _getOrCreateKey() async {
    try {
      final stored =
          await _secureStorage.read(key: _keyAlias, aOptions: _androidOptions);

      if (stored != null) {
        return Uint8List.fromList(base64Decode(stored));
      }
    } on PlatformException {
      await _secureStorage.deleteAll(aOptions: _androidOptions);
    }

    final key = Hive.generateSecureKey();
    await _secureStorage.write(
      key: _keyAlias,
      value: base64Encode(key),
      aOptions: _androidOptions,
    );
    return Uint8List.fromList(key);
  }

  static Box<SessionModel> get sessionBox =>
      Hive.box<SessionModel>(_sessionBox);
  static Box<TransactionModel> get txBox => Hive.box<TransactionModel>(_txBox);
  static Box get settingsBox => Hive.box(_settingsBox);
}

