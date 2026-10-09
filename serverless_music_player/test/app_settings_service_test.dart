import 'dart:io';

import 'package:auralis_player/services/app_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('persists the selected theme mode on device', () async {
    final directory = await Directory.systemTemp.createTemp('auralis-settings-test-');
    Hive.init(directory.path);

    try {
      final firstSettings = AppSettingsService();
      await firstSettings.init();
      expect(firstSettings.themeMode, ThemeMode.dark);
      await firstSettings.setThemeMode(ThemeMode.light);
      await Hive.box<dynamic>('app_settings').close();

      final restoredSettings = AppSettingsService();
      await restoredSettings.init();
      expect(restoredSettings.themeMode, ThemeMode.light);
      await restoredSettings.setThemeMode(ThemeMode.system);
      expect(restoredSettings.themeMode, ThemeMode.system);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
