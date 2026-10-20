import 'package:permission_handler/permission_handler.dart';

import 'app_log.dart';

/// Handles the Android 13+ notification permission that the playback
/// notification (media controls) depends on.
class NotificationService {
  static bool _requested = false;

  /// Asks once per app session. Returns true when notifications are allowed.
  static Future<bool> ensurePermission() async {
    try {
      var status = await Permission.notification.status;
      if (status.isGranted) return true;
      if (_requested) return status.isGranted;
      _requested = true;
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

  /// True when the user has allowed notifications (so the media controls can
  /// appear in the shade / lock screen).
  static Future<bool> areEnabled() async {
    try {
      return (await Permission.notification.status).isGranted;
    } catch (_) {
      return false;
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
