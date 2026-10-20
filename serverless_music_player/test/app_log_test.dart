import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/app_log.dart';

void main() {
  tearDown(AppLog.clear);

  test('captures entries in order with formatted output', () {
    logInfo('api', 'first event', <String, Object?>{'k': 1});
    logError('player', 'second event');

    final entries = AppLog.snapshot();
    expect(entries, hasLength(2));
    expect(entries.first.category, 'api');
    expect(entries.first.message, 'first event');
    expect(entries.first.data['k'], 1);
    expect(entries.last.level, LogLevel.error);
    expect(entries.first.format(), contains('INFO api: first event'));
    expect(entries.first.format(), contains('{k: 1}'));
  });

  test('ring buffer keeps only the most recent entries', () {
    for (var i = 0; i < AppLog.capacity + 50; i++) {
      logDebug('test', 'event $i');
    }
    expect(AppLog.entries.length, AppLog.capacity);
    expect(AppLog.entries.first.message, 'event 50');
    expect(AppLog.entries.last.message, 'event ${AppLog.capacity + 49}');
  });

  test('clear removes everything', () {
    logInfo('app', 'something');
    AppLog.clear();
    expect(AppLog.entries, isEmpty);
  });
}
