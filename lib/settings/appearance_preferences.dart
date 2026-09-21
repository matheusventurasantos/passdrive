import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppearancePreferences extends ChangeNotifier {
  static final instance = AppearancePreferences();
  static const _storage = FlutterSecureStorage();
  static const _key = 'passdrive.appearance.v1';
  ThemeMode mode = ThemeMode.system;
  double fontScale = 1;
  String language = 'pt';
  bool shareTheme = false;
  ThemeMode? _remoteMode;
  bool _saving = false;
  bool get saving => _saving;
  ThemeMode get effectiveMode => _remoteMode ?? mode;
  bool get dark =>
      effectiveMode == ThemeMode.dark ||
      (effectiveMode == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map;
      mode =
          ThemeMode.values.where((v) => v.name == data['mode']).firstOrNull ??
          ThemeMode.system;
      final scale = data['fontScale'];
      if (scale is num && scale.isFinite && scale >= 0.85 && scale <= 1.3) {
        fontScale = scale.toDouble();
      }
      language = data['language'] == 'en' ? 'en' : 'pt';
      shareTheme = data['shareTheme'] == true;
      notifyListeners();
    } on Object {
      // These presentation preferences are independent from the vault.
    }
  }

  Future<void> update({
    ThemeMode? mode,
    double? fontScale,
    String? language,
    bool? shareTheme,
  }) async {
    if (_saving) return;
    final nextMode = mode ?? this.mode;
    final nextScale = fontScale ?? this.fontScale;
    final nextLanguage = language ?? this.language;
    final nextShare = shareTheme ?? this.shareTheme;
    if (!nextScale.isFinite ||
        nextScale < 0.85 ||
        nextScale > 1.3 ||
        !['pt', 'en'].contains(nextLanguage)) {
      throw ArgumentError('Invalid preferences');
    }
    _saving = true;
    notifyListeners();
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'mode': nextMode.name,
          'fontScale': nextScale,
          'language': nextLanguage,
          'shareTheme': nextShare,
        }),
      );
      this.mode = nextMode;
      this.fontScale = nextScale;
      this.language = nextLanguage;
      this.shareTheme = nextShare;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  String? get sharedTheme => shareTheme ? (dark ? 'dark' : 'light') : null;
  void applyRemoteTheme(Object? value) {
    final next = value == 'dark'
        ? ThemeMode.dark
        : value == 'light'
        ? ThemeMode.light
        : null;
    if (_remoteMode == next) return;
    _remoteMode = next;
    notifyListeners();
  }
}
