import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AppSettingsService extends ChangeNotifier {
  static const String _boxName = 'app_settings';
  static const String _themeModeKey = 'theme_mode';

  late Box<dynamic> _settings;
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  Future<void> init() async {
    _settings = await Hive.openBox<dynamic>(_boxName);
    final saved = _settings.get(_themeModeKey)?.toString();
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _settings.put(_themeModeKey, mode.name);
    notifyListeners();
  }
}
