import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Image formats InstaGrab can export.
enum ImageFormat {
  png(label: 'PNG', extension: 'png'),
  jpeg(label: 'JPEG', extension: 'jpg');

  final String label;
  final String extension;
  const ImageFormat({required this.label, required this.extension});
}

/// Persistent user settings backed by [SharedPreferences].
///
/// Settings are read once on-demand and written immediately on change.
/// Callers receive a [SettingsSnapshot] — an immutable view of the
/// current values — and call [SettingsService.update] to change them.
class SettingsService {
  static const _keySavePath = 'save_path';
  static const _keyFormat = 'default_format';
  static const _keyWanlyApiKey = 'wanly_api_key';
  static const _keyWanlyApiUrl = 'wanly_api_url';
  static const _defaultWanlyApiUrl = 'http://api.wanly22.com:8001';

  /// Returns the current settings, filling in defaults for anything unset.
  static Future<SettingsSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savePath = prefs.getString(_keySavePath) ?? _defaultSavePath();
    final formatName = prefs.getString(_keyFormat) ?? ImageFormat.png.name;
    final format = ImageFormat.values.firstWhere(
      (f) => f.name == formatName,
      orElse: () => ImageFormat.png,
    );
    final apiKey = prefs.getString(_keyWanlyApiKey) ?? '';
    final apiUrl = prefs.getString(_keyWanlyApiUrl) ?? _defaultWanlyApiUrl;
    return SettingsSnapshot(
      savePath: savePath,
      format: format,
      wanlyApiKey: apiKey,
      wanlyApiUrl: apiUrl,
    );
  }

  /// Updates any provided fields; omits are left unchanged.
  static Future<SettingsSnapshot> update({
    String? savePath,
    ImageFormat? format,
    String? wanlyApiKey,
    String? wanlyApiUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (savePath != null) await prefs.setString(_keySavePath, savePath);
    if (format != null) await prefs.setString(_keyFormat, format.name);
    if (wanlyApiKey != null) {
      await prefs.setString(_keyWanlyApiKey, wanlyApiKey);
    }
    if (wanlyApiUrl != null) {
      await prefs.setString(_keyWanlyApiUrl, wanlyApiUrl);
    }
    return load();
  }

  static String _defaultSavePath() {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, 'Pictures', 'InstaGrab');
  }
}

/// Immutable snapshot of user settings at one point in time.
class SettingsSnapshot {
  final String savePath;
  final ImageFormat format;
  final String wanlyApiKey;
  final String wanlyApiUrl;
  const SettingsSnapshot({
    required this.savePath,
    required this.format,
    required this.wanlyApiKey,
    required this.wanlyApiUrl,
  });
}
