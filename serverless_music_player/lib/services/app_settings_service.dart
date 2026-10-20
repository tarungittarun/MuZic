import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AppSettingsService extends ChangeNotifier {
  static const String _boxName = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  static const String _lyricsLanguageKey = 'lyrics_language';
  static const String _lyricsOverridePrefix = 'lyrics_override:';
  static const String _virtualizerEnabledKey = 'virtualizer_enabled';
  static const String _virtualizerStrengthKey = 'virtualizer_strength';
  static const String _bassEnabledKey = 'bass_boost_enabled';
  static const String _bassStrengthKey = 'bass_boost_strength';
  static const String _eqEnabledKey = 'equalizer_enabled';
  static const String _eqPresetKey = 'equalizer_preset';
  static const String _diagnosticsKey = 'diagnostics_capture';

  late Box<dynamic> _settings;
  ThemeMode _themeMode = ThemeMode.dark;
  String _lyricsLanguage = 'auto';
  bool _virtualizerEnabled = false;
  int _virtualizerStrength = 60;
  bool _bassBoostEnabled = false;
  int _bassBoostStrength = 50;
  bool _equalizerEnabled = false;
  int _equalizerPreset = 0;
  bool _diagnosticsEnabled = false;

  ThemeMode get themeMode => _themeMode;

  /// Default lyrics language preference: 'auto', 'original', 'romanized' or a
  /// language name such as 'hindi'.
  String get lyricsLanguage => _lyricsLanguage;

  bool get virtualizerEnabled => _virtualizerEnabled;
  int get virtualizerStrength => _virtualizerStrength;
  bool get bassBoostEnabled => _bassBoostEnabled;
  int get bassBoostStrength => _bassBoostStrength;
  bool get equalizerEnabled => _equalizerEnabled;
  int get equalizerPreset => _equalizerPreset;

  /// Whether the user opted in to diagnostic capture. Off by default: nothing
  /// is recorded or exported unless they explicitly turn it on.
  bool get diagnosticsEnabled => _diagnosticsEnabled;

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
    _virtualizerEnabled = _settings.get(_virtualizerEnabledKey) == true;
    _virtualizerStrength = _readInt(_virtualizerStrengthKey, 60);
    _bassBoostEnabled = _settings.get(_bassEnabledKey) == true;
    _bassBoostStrength = _readInt(_bassStrengthKey, 50);
    _equalizerEnabled = _settings.get(_eqEnabledKey) == true;
    _equalizerPreset = _readInt(_eqPresetKey, 0);
    _diagnosticsEnabled = _settings.get(_diagnosticsKey) == true;
  }

  int _readInt(String key, int fallback) {
    final value = _settings.get(key);
    if (value is num) return value.toInt().clamp(0, 100).toInt();
    return fallback;
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

  Future<void> setDiagnosticsEnabled(bool value) async {
    _diagnosticsEnabled = value;
    await _settings.put(_diagnosticsKey, value);
    notifyListeners();
  }

  Future<void> setVirtualizer({required bool enabled, int? strength}) async {
    _virtualizerEnabled = enabled;
    if (strength != null) {
      _virtualizerStrength = strength.clamp(0, 100).toInt();
      await _settings.put(_virtualizerStrengthKey, _virtualizerStrength);
    }
    await _settings.put(_virtualizerEnabledKey, _virtualizerEnabled);
    notifyListeners();
  }

  Future<void> setBassBoost({required bool enabled, int? strength}) async {
    _bassBoostEnabled = enabled;
    if (strength != null) {
      _bassBoostStrength = strength.clamp(0, 100).toInt();
      await _settings.put(_bassStrengthKey, _bassBoostStrength);
    }
    await _settings.put(_bassEnabledKey, _bassBoostEnabled);
    notifyListeners();
  }

  Future<void> setEqualizer({required bool enabled, int? preset}) async {
    _equalizerEnabled = enabled;
    if (preset != null) {
      _equalizerPreset = preset.clamp(0, 9).toInt();
      await _settings.put(_eqPresetKey, _equalizerPreset);
    }
    await _settings.put(_eqEnabledKey, _equalizerEnabled);
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
