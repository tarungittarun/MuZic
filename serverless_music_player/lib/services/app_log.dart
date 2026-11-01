import 'package:flutter/foundation.dart';

/// Redacts user- and provider-specific values before they reach diagnostics or
/// Android's debug log. Network URLs can contain expiring media signatures.
String sanitizeLogText(String value) {
  var sanitized = value.replaceAll(
    RegExp(r'https?://[^\s<>"`]+', caseSensitive: false),
    '[network address redacted]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'''\b(authorization|auth|access[_-]?token|refresh[_-]?token|id[_-]?token|token|api[_-]?key|client[_-]?secret|private[_-]?key|credential(?:s)?|secret|password|signature|sig|set[_-]?cookie|cookie|session(?:[_-]?id)?)\b\s*([=:])\s*(?:[Bb]earer\s+)?(?:"[^"]*"|'[^']*'|[^\s,;}\]]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}${match.group(2)}[redacted]',
  );
  sanitized = sanitized
      .replaceAll(
        RegExp(r'(?:jio[\s_-]*)?saavn(?:cdn)?', caseSensitive: false),
        'Source A',
      )
      .replaceAll(
        RegExp(r'(?:youtube(?:[\s_-]*(?:music|explode(?:[\s_-]*dart)?))?|googlevideo|ytimg)',
            caseSensitive: false),
        'Source B',
      )
      .replaceAll(RegExp(r'lrclib', caseSensitive: false), 'lyrics source')
      .replaceAll(
        RegExp(r'radio[\s_-]*paradise', caseSensitive: false),
        'radio source',
      )
      .replaceAll(RegExp('spotify', caseSensitive: false), 'music source')
      .replaceAll(RegExp('motorola', caseSensitive: false), 'device')
      .replaceAll(RegExp('android', caseSensitive: false), 'system')
      .replaceAll(RegExp('google', caseSensitive: false), 'service')
      .replaceAll(RegExp('apple', caseSensitive: false), 'service')
      .replaceAll(RegExp('chrome', caseSensitive: false), 'browser')
      .replaceAll(RegExp(r'one\s*ui', caseSensitive: false), 'device interface');
  return sanitized;
}

bool _isSensitiveLogKey(String key) => RegExp(
      r'authorization|(^|[_-])auth([_-]|$)|token|api[_-]?key|client[_-]?secret|private[_-]?key|credential|password|signature|cookie|session|(^|[_-])secret([_-]|$)',
      caseSensitive: false,
    ).hasMatch(key);

Object? _sanitizeLogValue(Object? value) {
  if (value is String) return sanitizeLogText(value);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        sanitizeLogText(entry.key.toString()):
            _isSensitiveLogKey(entry.key.toString())
                ? '[redacted]'
                : _sanitizeLogValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map<Object?>(_sanitizeLogValue).toList(growable: false);
  }
  if (value == null || value is num || value is bool) return value;
  return sanitizeLogText(value.toString());
}

Map<String, Object?> _sanitizeLogData(Map<String, Object?> data) {
  return _sanitizeLogValue(data) as Map<String, Object?>;
}

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
    final buffer = StringBuffer(
      '[$stamp] $levelTag ${sanitizeLogText(category)}: '
      '${sanitizeLogText(message)}',
    );
    if (data.isNotEmpty) {
      buffer.write(' ');
      buffer.write(_sanitizeLogData(data));
    }
    return buffer.toString();
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'time': time.toIso8601String(),
        'level': level.name,
        'category': sanitizeLogText(category),
        'message': sanitizeLogText(message),
        if (data.isNotEmpty) 'data': _sanitizeLogData(data),
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
/// resolve, lyrics, player errors, queue state) for analysis. Sensitive
/// values, provider labels, and network URLs are redacted before storage.
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
      category: sanitizeLogText(category),
      message: sanitizeLogText(message),
      data: data == null ? const <String, Object?>{} : _sanitizeLogData(data),
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
