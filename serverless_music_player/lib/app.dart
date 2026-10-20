import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_info.dart';
import 'providers/player_controller.dart';
import 'services/app_settings_service.dart';
import 'services/audio_player_service.dart';
import 'services/diagnostics_service.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/music_api_service.dart';
import 'services/usage_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';

class MusicApp extends StatelessWidget {
  const MusicApp({
    required this.library,
    required this.musicApi,
    required this.audio,
    required this.downloads,
    required this.player,
    required this.settings,
    required this.usage,
    required this.diagnostics,
    super.key,
  });

  final LibraryService library;
  final MusicApiService musicApi;
  final AudioPlayerService audio;
  final DownloadService downloads;
  final PlayerController player;
  final AppSettingsService settings;
  final UsageService usage;
  final DiagnosticsService diagnostics;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryService>.value(value: library),
        Provider<MusicApiService>.value(value: musicApi),
        Provider<AudioPlayerService>.value(value: audio),
        Provider<DownloadService>.value(value: downloads),
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        ChangeNotifierProvider<UsageService>.value(value: usage),
        ChangeNotifierProvider<DiagnosticsService>.value(value: diagnostics),
      ],
      child: Consumer<AppSettingsService>(
        builder: (context, appSettings, _) => MaterialApp(
          title: AppInfo.displayName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: appSettings.themeMode,
          home: const MainShell(),
        ),
      ),
    );
  }
}
