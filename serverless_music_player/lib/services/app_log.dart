import 'package:flutter/foundation.dart';

/// Severity of a captured diagnostic log entry.
enum LogLevel { debug, info, warn, error }

/// One captured diagnostic record.
class LogEntry {
  LogEntry({
    required this.time,
    required this.level,
    required this.category,
    required this.message,
    this.data = const <String, Object?>{},
  });

  final DateTime time;
  final LogLevel level;
  final String category;
  final String message;
  final Map<String, Object?> data;

  String format() {
    final stamp = time.toIso8601String();
    final levelTag = level.name.toUpperCase();
    final buffer = StringBuffer('[$stamp] $levelTag $category: $message');
    if (data.isNotEmpty) {
      buffer.write(' ');
      buffer.write(data);
    }
    return buffer.toString();
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'time': time.toIso8601String(),
        'level': level.name,
        'category': category,
        'message': message,
        if (data.isNotEmpty) 'data': data,
      };
}

/// Returns the entries matching [levels] and the optional time window.
/// A null [start]/[end] leaves that side of the window open. The input order
/// is preserved, so callers that already reversed the snapshot keep newest
/// entries first.
List<LogEntry> filterLogEntries(
  Iterable<LogEntry> entries, {
  Set<LogLevel> levels = const <LogLevel>{
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  },
  DateTime? start,
  DateTime? end,
}) {
  return entries.where((entry) {
    if (!levels.contains(entry.level)) return false;
    if (start != null && entry.time.isBefore(start)) return false;
    if (end != null && entry.time.isAfter(end)) return false;
    return true;
  }).toList(growable: false);
}

/// Process-wide ring buffer of diagnostic log entries.
///
/// Capture is **opt-in**: nothing is recorded until the user turns on
/// "Capture diagnostics" in Settings. When enabled, services across the app
/// write here so a single export captures the full playback pipeline (search,
/// resolve, lyrics, player errors, queue state) for analysis.
class AppLog {
  AppLog._();

  static const int capacity = 4000;

  /// Master switch. Off by default; set from settings at startup.
  static bool enabled = false;

  static final List<LogEntry> entries = <LogEntry>[];
  static final List<void Function(LogEntry)> _listeners =
      <void Function(LogEntry)>[];

  static void log(
    LogLevel level,
    String category,
    String message, [
    Map<String, Object?>? data,
  ]) {
    if (!enabled) return;
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      category: category,
      message: message,
      data: data == null
          ? const <String, Object?>{}
          : Map<String, Object?>.of(data),
    );
    entries.add(entry);
    if (entries.length > capacity) {
      entries.removeRange(0, entries.length - capacity);
    }
    if (level == LogLevel.warn || level == LogLevel.error) {
      debugPrint(entry.format());
    }
    for (final listener in List<void Function(LogEntry)>.of(_listeners)) {
      listener(entry);
    }
  }

  /// Turns capture on or off. Turning it off also drops anything recorded.
  static void setEnabled(bool value) {
    enabled = value;
    if (!value) {
      clear();
    }
  }

  static void clear() => entries.clear();

  static List<LogEntry> snapshot() => List<LogEntry>.of(entries);

  static void addListener(void Function(LogEntry) listener) {
    _listeners.add(listener);
  }

  static void removeListener(void Function(LogEntry) listener) {
    _listeners.remove(listener);
  }
}

void logDebug(String category, String message, [Map<String, Object?>? data]) {
  if (!AppLog.enabled) return;
  AppLog.log(LogLevel.debug, category, message, data);
}

void logInfo(String category, String message, [Map<String, Object?>? data]) {
  if (!AppLog.enabled) return;
  AppLog.log(LogLevel.info, category, message, data);
}

void logWarn(String category, String message, [Map<String, Object?>? data]) {
  if (!AppLog.enabled) return;
  AppLog.log(LogLevel.warn, category, message, data);
}

void logError(String category, String message, [Map<String, Object?>? data]) {
  if (!AppLog.enabled) return;
  AppLog.log(LogLevel.error, category, message, data);
}
