import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/app_log.dart';

void main() {
  LogEntry at(String time, LogLevel level) => LogEntry(
        time: DateTime.parse(time),
        level: level,
        category: 'test',
        message: level.name,
      );

  final entries = <LogEntry>[
    at('2026-10-23T09:00:00', LogLevel.debug),
    at('2026-10-23T10:00:00', LogLevel.info),
    at('2026-10-23T11:00:00', LogLevel.warn),
    at('2026-10-23T12:00:00', LogLevel.error),
  ];

  test('filters diagnostics by type', () {
    final filtered = filterLogEntries(
      entries,
      levels: const <LogLevel>{LogLevel.error, LogLevel.info},
    );
    expect(filtered.map((entry) => entry.level), <LogLevel>[
      LogLevel.info,
      LogLevel.error,
    ]);
  });

  test('filters diagnostics by inclusive time window', () {
    final filtered = filterLogEntries(
      entries,
      start: DateTime.parse('2026-10-23T10:00:00'),
      end: DateTime.parse('2026-10-23T11:00:00'),
    );
    expect(filtered.map((entry) => entry.level), <LogLevel>[
      LogLevel.info,
      LogLevel.warn,
    ]);
  });
}
