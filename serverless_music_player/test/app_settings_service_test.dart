import 'dart:io';

import 'package:music_player/services/app_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('persists the selected theme mode on device', () async {
    final directory = await Directory.systemTemp.createTemp('music-settings-test-');
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

  test('diagnostics stays off by default and sleep timer persists',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('music-prefs-test-');
    Hive.init(directory.path);

    try {
      final first = AppSettingsService();
      await first.init();
      // Diagnostics capture is opt-in and must default to off.
      expect(first.diagnosticsEnabled, isFalse);
      expect(first.sleepTimerEnabled, isFalse);
      expect(first.sleepTimerMinutes, 60);
      expect(first.region, 'IN');
      expect(first.languages, containsAll(<String>['hindi', 'english']));

      await first.setDiagnosticsEnabled(true);
      await first.setSleepTimer(enabled: true, minutes: 45);
      await first.setRegion('US');
      await first.setLanguages(<String>['english']);
      await Hive.box<dynamic>('app_settings').close();

      final restored = AppSettingsService();
      await restored.init();
      expect(restored.diagnosticsEnabled, isTrue);
      expect(restored.sleepTimerEnabled, isTrue);
      expect(restored.sleepTimerMinutes, 45);
      expect(restored.region, 'US');
      expect(restored.languages, <String>['english']);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
