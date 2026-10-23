import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../providers/player_controller.dart';
import 'app_log.dart';
import 'app_settings_service.dart';

/// Pauses playback when the user has been inactive for a chosen duration.
///
/// Timeline (defaults): after [inactivity] minutes without any app interaction
/// a warning notification is posted; if the user still does not interact
/// within [warningWindow], playback pauses.
class SleepTimerService extends ChangeNotifier with WidgetsBindingObserver {
  SleepTimerService({
    required this.settings,
    required this.player,
    this.warningWindow = const Duration(minutes: 5),
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('music_player/system');

  final AppSettingsService settings;
  final PlayerController player;
  final Duration warningWindow;
  final MethodChannel _channel;

  DateTime _lastActivity = DateTime.now();
  DateTime? _warningShownAt;
  Timer? _ticker;
  bool _started = false;

  /// When true the user is watching something in the app; exposed so the UI can
  /// show the countdown.
  bool get isWarningActive => _warningShownAt != null;

  Duration get inactivity =>
      Duration(minutes: settings.sleepTimerMinutes);

  Duration get remaining {
    if (_warningShownAt != null) {
      final elapsed = DateTime.now().difference(_warningShownAt!);
      final left = warningWindow - elapsed;
      return left.isNegative ? Duration.zero : left;
    }
    final elapsed = DateTime.now().difference(_lastActivity);
    final left = inactivity - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    logInfo('sleep', 'sleep timer service started', <String, Object?>{
      'enabled': settings.sleepTimerEnabled,
      'minutes': settings.sleepTimerMinutes,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) registerActivity();
  }

  /// Call on any interaction (tap, scroll, search, transport control).
  void registerActivity() {
    _lastActivity = DateTime.now();
    if (_warningShownAt != null) {
      _warningShownAt = null;
      unawaited(_cancelNotification(1001));
      logInfo('sleep', 'user acknowledged, timer reset');
      notifyListeners();
    }
  }

  Future<void> _tick() async {
    if (!settings.sleepTimerEnabled) {
      if (_warningShownAt != null) {
        _warningShownAt = null;
        await _cancelNotification(1001);
        notifyListeners();
      }
      return;
    }
    if (!player.isPlaying) {
      // Playback is stopped; nothing to protect against. Reset the clock so a
      // later session starts fresh.
      _lastActivity = DateTime.now();
      if (_warningShownAt != null) {
        _warningShownAt = null;
        await _cancelNotification(1001);
        notifyListeners();
      }
      return;
    }
    notifyListeners();

    final idle = DateTime.now().difference(_lastActivity);
    if (_warningShownAt == null && idle >= inactivity) {
      _warningShownAt = DateTime.now();
      await _postWarning();
      notifyListeners();
      return;
    }
    if (_warningShownAt != null &&
        DateTime.now().difference(_warningShownAt!) >= warningWindow) {
      await _pauseForSleep();
    }
  }

  Future<void> _postWarning() async {
    final minutes = warningWindow.inMinutes;
    logInfo('sleep', 'inactivity warning posted', <String, Object?>{
      'idleMinutes': DateTime.now().difference(_lastActivity).inMinutes,
      'sleepTimerMinutes': settings.sleepTimerMinutes,
    });
    await _notify(
      1001,
      'Still listening?',
      'MuZic will pause playback in $minutes minutes because there has been no '
          'activity. Open the app or tap play to keep listening.',
    );
  }

  Future<void> _pauseForSleep() async {
    logInfo('sleep', 'pausing playback due to inactivity');
    await player.pause();
    _warningShownAt = null;
    _lastActivity = DateTime.now();
    await _notify(
      1002,
      'Playback paused',
      'MuZic paused because there was no activity for '
          '${settings.sleepTimerMinutes} minutes.',
    );
    notifyListeners();
  }

  Future<void> _notify(int id, String title, String body) async {
    try {
      await _channel.invokeMethod<bool>('notify', <String, Object?>{
        'id': id,
        'title': title,
        'body': body,
        'channelId': 'muzic_sleep_alerts',
        'channelName': 'MuZic sleep timer',
      });
    } on MissingPluginException {
      // Non-Android: the in-app banner still works.
    } on PlatformException catch (error) {
      logWarn('sleep', 'notification failed', <String, Object?>{
        'error': '$error',
      });
    }
  }

  Future<void> _cancelNotification(int id) async {
    try {
      await _channel.invokeMethod<bool>('cancel', <String, Object?>{'id': id});
    } on MissingPluginException {
      // Ignore.
    } on PlatformException {
      // Ignore.
    }
  }

  /// Lets the user postpone the pause from the in-app banner.
  void snooze() {
    registerActivity();
    logInfo('sleep', 'sleep timer snoozed by user');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
