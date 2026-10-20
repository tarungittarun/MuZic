import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'providers/player_controller.dart';
import 'services/app_log.dart';
import 'services/app_settings_service.dart';
import 'services/audio_effects_service.dart';
import 'services/audio_player_service.dart';
import 'services/diagnostics_service.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/music_api_service.dart';
import 'services/usage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture framework and async errors into the diagnostics log so they can
  // be exported and shared for analysis.
  final previousOnError = foundation.FlutterError.onError;
  foundation.FlutterError.onError = (foundation.FlutterErrorDetails details) {
    logError('flutter', details.exceptionAsString(), <String, Object?>{
      'library': details.library ?? '',
    });
    previousOnError?.call(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    logError('zone', '$error', <String, Object?>{
      'stack': stack.toString().split('\n').take(6).join(' | '),
    });
    return true;
  };

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.music.player.audio',
    androidNotificationChannelName: 'MuZic playback',
    androidNotificationOngoing: true,
  );

  final library = LibraryService();
  await library.init();
  final settings = AppSettingsService();
  await settings.init();
  final usage = UsageService();
  await usage.init();

  final musicApi = MusicApiService();
  final audio = AudioPlayerService();
  final downloads = DownloadService(library: library);
  final player = PlayerController(
    audio: audio,
    musicApi: musicApi,
    downloads: downloads,
    library: library,
    usage: usage,
  );
  final diagnostics = DiagnosticsService(
    settings: settings,
    library: library,
    usage: usage,
    player: player,
    musicApi: musicApi,
  );
  final effects = AudioEffectsService(settings: settings, player: audio.player);
  effects.attach();

  logInfo('app', 'application starting');

  runApp(MusicApp(
    library: library,
    musicApi: musicApi,
    audio: audio,
    downloads: downloads,
    player: player,
    settings: settings,
    usage: usage,
    diagnostics: diagnostics,
    effects: effects,
  ));
}
