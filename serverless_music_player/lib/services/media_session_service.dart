import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

/// Everything the playback card needs to render.
@immutable
class MediaSessionState {
  const MediaSessionState({
    required this.title,
    required this.artist,
    this.album = '',
    this.artworkUrl,
    this.artworkPath,
    this.playing = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.speed = 1,
    this.hasNext = false,
    this.hasPrevious = false,
    this.shadeEnabled = true,
    this.shadeStyle = 'rich',
    this.shadeTheme = 'system',
    this.shadeArtwork = true,
    this.shadePrevious = true,
    this.shadeNext = true,
    this.shadeProgress = true,
    this.shadeKeepOnPause = true,
  });

  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;
  final String? artworkPath;
  final bool playing;
  final int positionMs;
  final int durationMs;
  final double speed;
  final bool hasNext;
  final bool hasPrevious;

  /// User customisation for the notification-panel (shade) card. Mirrors the
  /// notification settings; applied by the native PlaybackService.
  final bool shadeEnabled;
  final String shadeStyle;
  final String shadeTheme;
  final bool shadeArtwork;
  final bool shadePrevious;
  final bool shadeNext;
  final bool shadeProgress;
  final bool shadeKeepOnPause;

  /// Identity of the track, used to avoid pointless re-posts.
  String get trackKey => '$title|$artist|${artworkPath ?? artworkUrl ?? ''}';

  /// Identity of the shade-card options, so a settings change re-posts the
  /// card even when the track and position have not moved.
  String get configKey => '$shadeEnabled|$shadeStyle|$shadeTheme|'
      '$shadeArtwork|$shadePrevious|$shadeNext|$shadeProgress|'
      '$shadeKeepOnPause';

  Map<String, Object?> toMap() => <String, Object?>{
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'artworkPath': artworkPath,
        'playing': playing,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': speed,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
        'shadeEnabled': shadeEnabled,
        'shadeStyle': shadeStyle,
        'shadeTheme': shadeTheme,
        'shadeArtwork': shadeArtwork,
        'shadePrevious': shadePrevious,
        'shadeNext': shadeNext,
        'shadeProgress': shadeProgress,
        'shadeKeepOnPause': shadeKeepOnPause,
      };
}

/// Publishes the player state to MuZic's native playback card.
///
/// The card itself is built in Kotlin (`PlaybackService`) with a real
/// MediaSessionCompat and a MediaStyle notification, because the previous,
/// plugin-provided notification was posted on some devices but never rendered
/// as a media player. Transport buttons on the card come back here and are
/// forwarded to [onCommand].
class MediaSessionService {
  MediaSessionService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('music_player/media_session') {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;

  /// Called with `play`, `pause`, `toggle`, `next`, `previous`, `stop` and
  /// `seek` (with a position in milliseconds).
  void Function(String command, double? value)? onCommand;

  String? _lastTrackKey;
  String? _lastConfigKey;
  bool? _lastPlaying;
  int _lastPostedPosition = -10000;

  /// Pushes [state] to the notification. Position-only changes are throttled so
  /// the notification is not re-posted on every tick.
  Future<void> update(MediaSessionState state) async {
    final trackChanged = state.trackKey != _lastTrackKey;
    final configChanged = state.configKey != _lastConfigKey;
    final playChanged = state.playing != _lastPlaying;
    final positionJumped =
        (state.positionMs - _lastPostedPosition).abs() > 3000;
    if (!trackChanged && !configChanged && !playChanged && !positionJumped) {
      return;
    }
    _lastTrackKey = state.trackKey;
    _lastConfigKey = state.configKey;
    _lastPlaying = state.playing;
    _lastPostedPosition = state.positionMs;
    try {
      await _channel.invokeMethod<bool>('update', state.toMap());
    } on MissingPluginException {
      // Desktop/other platforms have no playback card.
    } on PlatformException catch (error) {
      logWarn('media_session', 'update failed', <String, Object?>{
        'error': '${error.code}: ${error.message}',
      });
    }
  }

  /// Removes the card (playback finished or stopped by the user).
  Future<void> hide() async {
    _lastTrackKey = null;
    _lastConfigKey = null;
    _lastPlaying = null;
    _lastPostedPosition = -10000;
    try {
      await _channel.invokeMethod<bool>('hide');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'onLog') {
      // Native-side playback card failure; surface it in diagnostics
      // instead of letting it disappear without a trace.
      final args = call.arguments;
      final message = args is Map ? args['message']?.toString() : null;
      logWarn('notification', message ?? 'native card error');
      return null;
    }
    if (call.method != 'onCommand') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final command = args['command']?.toString();
    if (command == null) return null;
    final rawValue = args['value'];
    final value = rawValue is num ? rawValue.toDouble() : null;
    logInfo('media_session', 'card command', <String, Object?>{
      'command': command,
      'value': value,
    });
    onCommand?.call(command, value);
    return null;
  }
}
