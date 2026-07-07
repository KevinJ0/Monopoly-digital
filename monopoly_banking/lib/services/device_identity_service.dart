import 'dart:async';

import 'package:monopoly_banking/services/hive_service.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const _installationIdKey = 'device_installation_id_v1';
  static String? _installationId;

  static String get installationId {
    final cached = _installationId;
    if (cached != null && cached.isNotEmpty) return cached;

    final stored = HiveService.settingsBox.get(_installationIdKey) as String?;
    if (stored != null && stored.isNotEmpty) {
      _installationId = stored;
      return stored;
    }

    final generated = const Uuid().v4();
    _installationId = generated;
    unawaited(HiveService.settingsBox.put(_installationIdKey, generated));
    return generated;
  }
}
