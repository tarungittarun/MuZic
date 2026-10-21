import 'package:flutter/foundation.dart' as foundation;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'providers/player_controller.dart';
import 'services/app_log.dart';
import 'services/app_settings_service.dart';
import 'services/audio_handler.dart';
import 'services/audio_effects_service.dart';
import 'services/audio_player_service.dart';
import 'services/diagnostics_service.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/music_api_service.dart';
import 'services/notification_service.dart';
import 'services/sleep_timer_service.dart';
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

  // Registers the media session that backs the playback notification, lock
  // screen and Bluetooth/headset controls.
  await AudioService.init(
    builder: () => MuzicAudioHandler(audio.player, settings),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.music.player.audio',
      androidNotificationChannelName: 'MuZic playback',
      // audio_service asserts that an "ongoing" (non-dismissible) card is only
      // valid when the service leaves the foreground on pause - which would
      // remove the card as soon as playback pauses. Keeping the card visible
      // while paused is a product requirement, so the card stays dismissible.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: !settings.keepNotificationOnPause,
      androidNotificationClickStartsActivity: true,
      androidNotificationIcon: 'drawable/ic_stat_muzic',
    ),
  );

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
  ));

  // Ask for notification access once the UI is up: Android only shows the
  // system dialog from a resumed activity, so asking before runApp fails
  // silently — which is why the media notification never appeared.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.ensurePermission();
  });
}
