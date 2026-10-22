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
import 'services/notification_service.dart';
import 'services/sleep_timer_service.dart';
import 'services/usage_service.dart';
import 'services/video_export_manager.dart';
import 'services/video_library_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The music controller is the system media player (notification shade,
  // lock screen, Quick Settings, Bluetooth), provided by
  // just_audio_background + audio_service from the MediaItem tags on every
  // audio source - the same setup as the main branch. Must be initialised
  // before the AudioPlayer is created.
  // Identical to the main branch: same plugin, same channel, same flags.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.auralis.player.audio',
    androidNotificationChannelName: 'MuZic playback',
    androidNotificationOngoing: true,
    // Lets Android treat MuZic as a browsable/resumable media source where
    // the phone and Google media stack support Quick Settings resumption
    // or recommendations. Android still decides whether to surface them.
    androidBrowsableRootExtras: const <String, dynamic>{
      'android.media.browse.CONTENT_STYLE_SUPPORTED': true,
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1,
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 1,
    },
  );

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

  final downloads = DownloadService(library: library, settings: appSettings);
  final videoLibrary = VideoLibraryService();
  await videoLibrary.init();
  final videoExports = VideoExportManager();
  // MuZic deliberately adds no separate notification-shade card. Playback
  // notifications come only from Android's system media player above.
  final player = PlayerController(
    audio: audio,
    musicApi: musicApi,
    downloads: downloads,
    library: library,
    usage: usage,
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
