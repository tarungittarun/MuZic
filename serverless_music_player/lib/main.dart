import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

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
import 'services/notification_service.dart';
import 'services/sleep_timer_service.dart';
import 'services/media_session_service.dart';
import 'services/usage_service.dart';
import 'services/video_export_manager.dart';
import 'services/video_library_service.dart';

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

  final library = LibraryService();
  await library.init();
  final settings = AppSettingsService();
  await settings.init();
  // Diagnostics are opt-in: nothing is captured until the user enables it.
  AppLog.setEnabled(settings.diagnosticsEnabled);
  final usage = UsageService();
  await usage.init();

  final musicApi = MusicApiService();
  final audio = AudioPlayerService();

  // MuZic owns its playback card: a native MediaSession + MediaStyle
  // notification (PlaybackService) driven from here. The audio_service plugin
  // was removed after its notification was posted on some devices but never
  // rendered as a media player.
  final mediaSession = MediaSessionService();

  final downloads = DownloadService(library: library);
  final videoLibrary = VideoLibraryService();
  await videoLibrary.init();
  final videoExports = VideoExportManager();
  final player = PlayerController(
    audio: audio,
    musicApi: musicApi,
    downloads: downloads,
    library: library,
    usage: usage,
    mediaSession: mediaSession,
    settings: settings,
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
  final sleepTimer = SleepTimerService(settings: settings, player: player);
  sleepTimer.start();


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
    sleepTimer: sleepTimer,
    videoExports: videoExports,
    videoLibrary: videoLibrary,
  ));

  // Ask for notification access once the UI is up: Android only shows the
  // system dialog from a resumed activity, so asking before runApp fails
  // silently — which is why the media notification never appeared.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.ensurePermission();
  });
}
