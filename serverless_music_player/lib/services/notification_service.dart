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
