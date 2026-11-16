import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small settings for the bank-alert feature.
///
/// Your name is saved in the same secure storage as the PIN, not in plain
/// settings, because it is personal.
class AlertSettings {
  // Only static methods, so nobody should create an instance.
  AlertSettings._();

  static const _storage = FlutterSecureStorage();
  static const _kNames = 'alert_my_names';

  /// Your names as they appear in bank alerts, e.g. ["ADA OKAFOR"].
  /// Alerts mentioning one are treated as moves between your own accounts.
  static Future<List<String>> myNames() async {
    final text = await _storage.read(key: _kNames) ?? '';
    return text
        .split('\n')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  static Future<void> setMyNames(List<String> names) async {
    final cleaned = names.map((n) => n.trim()).where((n) => n.isNotEmpty);
    if (cleaned.isEmpty) {
      await _storage.delete(key: _kNames);
    } else {
      await _storage.write(key: _kNames, value: cleaned.join('\n'));
    }
  }
}
