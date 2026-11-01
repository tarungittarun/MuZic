import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'app_log.dart';
import 'app_settings_service.dart';

/// Applies Android's Equalizer / BassBoost / Virtualizer (virtual surround)
/// to the playback audio session via a platform channel hosted by MainActivity.
class AudioEffectsService {
  AudioEffectsService({
    required this.settings,
    required this.player,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('music_player/audio_effects');

  final AppSettingsService settings;
  final AudioPlayer player;
  final MethodChannel _channel;

  bool _attached = false;

  /// Starts listening for audio-session changes and applies the saved
  /// effect settings whenever the session becomes available.
  void attach() {
    if (_attached) return;
    _attached = true;
    player.androidAudioSessionIdStream.listen((sessionId) {
      logInfo('effects', 'audio session changed', <String, Object?>{
        'sessionId': sessionId,
      });
      unawaited(apply(sessionId: sessionId));
    });
    unawaited(apply());
  }

  /// Applies the current settings to [sessionId] (or the player's current
  /// session). Returns false when effects could not be applied.
  Future<bool> apply({int? sessionId}) async {
    final id = sessionId ?? player.androidAudioSessionId ?? 0;
    try {
      final ok = await _channel.invokeMethod<bool>('apply', <String, Object?>{
        'sessionId': id,
        'virtualizerEnabled': settings.virtualizerEnabled,
        'virtualizerStrength': settings.virtualizerStrength,
        'bassEnabled': settings.bassBoostEnabled,
        'bassStrength': settings.bassBoostStrength,
        'eqEnabled': settings.equalizerEnabled,
        'eqPreset': settings.equalizerPreset,
      });
      logInfo('effects', 'effects applied', <String, Object?>{
        'sessionId': id,
        'virtualizer': settings.virtualizerEnabled,
        'bass': settings.bassBoostEnabled,
        'equalizer': settings.equalizerEnabled,
        'ok': ok,
      });
      return ok ?? false;
    } on MissingPluginException {
      logWarn('effects', 'audio effects not available on this platform');
      return false;
    } on PlatformException catch (error) {
      logWarn('effects', 'apply failed', <String, Object?>{'error': '$error'});
      return false;
    }
  }

  Future<void> release() async {
    try {
      await _channel.invokeMethod<bool>('release');
    } on MissingPluginException {
      // Not available on this platform; nothing to release.
    } on PlatformException catch (error) {
      logWarn('effects', 'release failed', <String, Object?>{'error': '$error'});
    }
  }
}
