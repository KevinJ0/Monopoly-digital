import 'dart:async';

import 'package:monopoly_banking/services/hive_service.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const _installationIdKey = 'device_installation_id_v1';

  static String get installationId {
    final stored = HiveService.settingsBox.get(_installationIdKey) as String?;
    if (stored != null && stored.isNotEmpty) return stored;

    final generated = const Uuid().v4();
    unawaited(HiveService.settingsBox.put(_installationIdKey, generated));
    return generated;
  }
}
