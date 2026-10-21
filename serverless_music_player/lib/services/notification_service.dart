import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_log.dart';

/// Handles the Android 13+ notification permission that the playback
/// notification (media controls) depends on.
class NotificationService {
  static bool _requestedThisSession = false;

  /// Asks once per app session. Returns true when notifications are allowed.
  static Future<bool> ensurePermission({bool force = false}) async {
    try {
      var status = await Permission.notification.status;
      if (status.isGranted) {
        logInfo('notification', 'permission already granted');
        return true;
      }
      if (_requestedThisSession && !force) {
        logInfo('notification', 'permission still not granted',
            <String, Object?>{'status': status.name});
        return status.isGranted;
      }
      _requestedThisSession = true;
      status = await Permission.notification.request();
      logInfo('notification', 'permission result', <String, Object?>{
        'granted': status.isGranted,
        'status': status.name,
      });
      return status.isGranted;
    } catch (error) {
      logWarn('notification', 'permission check failed',
          <String, Object?>{'error': '$error'});
      return false;
    }
  }

  /// Cached snapshot of what Android is currently showing for MuZic; included
  /// in exported diagnostics reports.
  static String lastStatus = 'not checked';

  /// Asks the platform which notifications are currently visible. A media
  /// card that never appears shows up here as a missing notification.
  static Future<String> refreshStatus() async {
    try {
      final raw = await const MethodChannel('music_player/system')
          .invokeMethod<List<dynamic>>('activeNotifications');
      if (raw == null) {
        lastStatus = 'unavailable';
        return lastStatus;
      }
      if (raw.isEmpty) {
        lastStatus = '0 active notifications';
        return lastStatus;
      }
      final parts = <String>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        parts.add(
          '#${map['id']} ch=${map['channelId']} ongoing=${map['ongoing']} '
          'title=${map['title']}',
        );
      }
      lastStatus = '${raw.length} active: ${parts.join(' | ')}';
      logInfo('notification', 'active notifications', <String, Object?>{
        'status': lastStatus,
      });
      return lastStatus;
    } on MissingPluginException {
      lastStatus = 'unavailable on this platform';
      return lastStatus;
    } on PlatformException catch (error) {
      lastStatus = 'error: $error';
      return lastStatus;
    }
  }

  /// Posts a plain test notification so the user can confirm MuZic is able to
  /// display notifications at all (separate from the media card).
  static Future<bool> sendTest() async {
    try {
      final ok = await const MethodChannel('music_player/system')
          .invokeMethod<bool>('notify', <String, Object?>{
        'id': 2001,
        'title': 'MuZic notifications work',
        'body': 'If you can read this in the shade, playback controls can show '
            'up here too while music plays.',
        'channelId': 'muzic_test',
        'channelName': 'MuZic test',
      });
      logInfo('notification', 'test notification posted', <String, Object?>{
        'ok': ok,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      logWarn('notification', 'test notification failed',
          <String, Object?>{'error': '$error'});
      return false;
    }
  }

  /// Full chain report for the media card, straight from Android.
  ///
  /// Returns human-readable lines so the Settings screen can show exactly
  /// which link is broken when no playback card appears.
  static Future<List<String>> healthReport() async {
    try {
      final raw = await const MethodChannel('music_player/system')
          .invokeMethod<Map<dynamic, dynamic>>('mediaNotificationDiagnostics');
      if (raw == null) return const <String>['Unavailable on this device.'];
      final enabled = raw['notificationsEnabled'] == true;
      final permission = raw['postPermission'] == true;
      final channel = raw['playbackChannelExists'] == true;
      final importance = raw['playbackChannelImportance'];
      final service = raw['audioServiceDeclared'] == true;
      final icon = raw['smallIconResolves'] == true;
      final posted = raw['postedCount'] ?? 0;
      final lines = <String>[
        '${enabled ? '✅' : '❌'} Notifications allowed for MuZic',
        '${permission ? '✅' : '❌'} Notification permission granted',
        '${channel ? '✅' : '❌'} Playback channel created'
            '${channel ? ' (importance $importance)' : ''}',
        '${service ? '✅' : '❌'} Playback service declared',
        '${icon ? '✅' : '❌'} Notification icon in build',
        '${posted is int && posted > 0 ? '✅' : '⚠️'} '
            '$posted MuZic notification(s) showing now',
      ];
      final sessionActive = raw['mediaSessionActive'] == true;
      lines.add('${sessionActive ? '✅' : '⚠️'} Media session '
          '${sessionActive ? 'active (lock-screen / Quick Settings player)' : 'not active'}');
      final postedEntries = raw['posted'];
      final playerShowing = postedEntries is List &&
          postedEntries.any(
              (entry) => entry.toString().contains('com.auralis.player.muzic.audio'));
      lines.add('${playerShowing ? '✅' : '⚠️'} System media player '
          '${playerShowing ? 'showing' : 'not showing — play a song, then pull down the shade'}');
      if (importance is int && importance == 0) {
        lines.add('This channel is turned off in Android settings — open '
            'notification settings and turn MuZic back on.');
      }
      return lines;
    } on MissingPluginException {
      return const <String>['Unavailable on this platform.'];
    } on PlatformException catch (error) {
      return <String>['Error: ${error.message ?? error.code}'];
    }
  }

  /// Current notification permission state, without prompting.
  static Future<bool> areEnabled() async {
    try {
      return (await Permission.notification.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Battery-optimisation exemption. Several Chinese OEM skins (MIUI, ColorOS,
  /// FuntouchOS) kill the media notification unless the app is exempt.
  static Future<bool> isBatteryUnrestricted() async {
    try {
      return (await Permission.ignoreBatteryOptimizations.status).isGranted;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestBatteryExemption() async {
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (error) {
      logWarn('notification', 'battery exemption request failed',
          <String, Object?>{'error': '$error'});
    }
  }

  /// Opens the system screen for this app so the user can fix blocked
  /// notifications (common on Xiaomi/OPPO/vivo devices).
  static Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (error) {
      logWarn('notification', 'could not open app settings',
          <String, Object?>{'error': '$error'});
    }
  }
}
