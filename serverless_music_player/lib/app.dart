import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/player_controller.dart';
import 'screens/main_shell.dart';
import 'services/app_settings_service.dart';
import 'services/audio_player_service.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/music_api_service.dart';
import 'services/usage_service.dart';
import 'theme/app_theme.dart';

class AuralisApp extends StatelessWidget {
  const AuralisApp({
    required this.library,
    required this.musicApi,
    required this.audio,
    required this.downloads,
    required this.player,
    required this.settings,
    required this.usage,
    super.key,
  });

  final LibraryService library;
  final MusicApiService musicApi;
  final AudioPlayerService audio;
  final DownloadService downloads;
  final PlayerController player;
  final AppSettingsService settings;
  final UsageService usage;

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
      ],
      child: Consumer<AppSettingsService>(
        builder: (context, appSettings, _) => MaterialApp(
          title: 'Auralis',
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
