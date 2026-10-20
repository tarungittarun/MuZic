import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AppSettingsService extends ChangeNotifier {
  static const String _boxName = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  static const String _lyricsLanguageKey = 'lyrics_language';
  static const String _lyricsOverridePrefix = 'lyrics_override:';

  late Box<dynamic> _settings;
  ThemeMode _themeMode = ThemeMode.dark;
  String _lyricsLanguage = 'auto';

  ThemeMode get themeMode => _themeMode;

  /// Default lyrics language preference: 'auto', 'original', 'romanized' or a
  /// language name such as 'hindi'.
  String get lyricsLanguage => _lyricsLanguage;

  Future<void> init() async {
    _settings = await Hive.openBox<dynamic>(_boxName);
    final saved = _settings.get(_themeModeKey)?.toString();
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.dark,
    );
    final savedLanguage =
        _settings.get(_lyricsLanguageKey)?.toString().trim() ?? '';
    _lyricsLanguage = savedLanguage.isEmpty ? 'auto' : savedLanguage;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _settings.put(_themeModeKey, mode.name);
    notifyListeners();
  }

  Future<void> setLyricsLanguage(String code) async {
    final clean = code.trim().isEmpty ? 'auto' : code.trim();
    if (clean == _lyricsLanguage) return;
    _lyricsLanguage = clean;
    await _settings.put(_lyricsLanguageKey, clean);
    notifyListeners();
  }

  /// Per-song lyrics language override ('' means follow the default).
  String lyricsLanguageOverrideFor(String songId) {
    final value = _settings.get('$_lyricsOverridePrefix$songId');
    return value?.toString() ?? '';
  }

  Future<void> setLyricsLanguageOverride(String songId, String? code) async {
    final key = '$_lyricsOverridePrefix$songId';
    final clean = (code ?? '').trim();
    if (clean.isEmpty) {
      await _settings.delete(key);
    } else {
      await _settings.put(key, clean);
    }
    notifyListeners();
  }
}
