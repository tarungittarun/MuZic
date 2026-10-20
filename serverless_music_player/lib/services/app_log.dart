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

/// Process-wide ring buffer of diagnostic log entries.
///
/// Services across the app write here so a single export can capture the full
/// playback pipeline (search, resolve, lyrics, player errors) for analysis.
class AppLog {
  AppLog._();

  static const int capacity = 2500;
  static final List<LogEntry> entries = <LogEntry>[];
  static final List<void Function(LogEntry)> _listeners =
      <void Function(LogEntry)>[];

  static void log(
    LogLevel level,
    String category,
    String message, [
    Map<String, Object?>? data,
  ]) {
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

  static void clear() => entries.clear();

  static List<LogEntry> snapshot() => List<LogEntry>.of(entries);

  static void addListener(void Function(LogEntry) listener) {
    _listeners.add(listener);
  }

  static void removeListener(void Function(LogEntry) listener) {
    _listeners.remove(listener);
  }
}

void logDebug(String category, String message, [Map<String, Object?>? data]) =>
    AppLog.log(LogLevel.debug, category, message, data);

void logInfo(String category, String message, [Map<String, Object?>? data]) =>
    AppLog.log(LogLevel.info, category, message, data);

void logWarn(String category, String message, [Map<String, Object?>? data]) =>
    AppLog.log(LogLevel.warn, category, message, data);

void logError(String category, String message, [Map<String, Object?>? data]) =>
    AppLog.log(LogLevel.error, category, message, data);
