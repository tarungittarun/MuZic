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

  test('shade card preferences default rich/system and persist', () async {
    final directory =
        await Directory.systemTemp.createTemp('music-shade-test-');
    Hive.init(directory.path);

    try {
      final first = AppSettingsService();
      await first.init();
      expect(first.shadeCardStyle, 'rich');
      expect(first.shadeCardTheme, 'system');
      expect(first.shadeCardArtwork, isTrue);
      expect(first.notificationEnabled, isTrue);
      expect(first.keepNotificationOnPause, isTrue);

      await first.setShadeCardStyle('simple');
      await first.setShadeCardTheme('dark');
      await first.setShadeCardArtwork(false);
      // Unknown values normalise to the safe defaults.
      await first.setShadeCardStyle('neon');
      expect(first.shadeCardStyle, 'rich');
      await first.setShadeCardTheme('neon');
      expect(first.shadeCardTheme, 'system');
      await Hive.box<dynamic>('app_settings').close();

      final restored = AppSettingsService();
      await restored.init();
      expect(restored.shadeCardStyle, 'rich');
      expect(restored.shadeCardTheme, 'system');
      expect(restored.shadeCardArtwork, isFalse);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
