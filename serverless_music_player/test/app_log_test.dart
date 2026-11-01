import 'package:flutter_test/flutter_test.dart';
import 'package:muzic/services/app_log.dart';

void main() {
  setUp(() => AppLog.setEnabled(true));
  tearDown(() {
    AppLog.clear();
    AppLog.setEnabled(false);
  });

  test('captures nothing while disabled', () {
    AppLog.setEnabled(false);
    logInfo('api', 'should be ignored');
    logError('player', 'also ignored');
    expect(AppLog.entries, isEmpty);
  });

  test('disabling capture deletes what was recorded', () {
    logInfo('api', 'kept briefly');
    expect(AppLog.entries, hasLength(1));
    AppLog.setEnabled(false);
    expect(AppLog.entries, isEmpty);
  });

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

  test('redacts provider names, network URLs, and credential-like fields', () {
    logError(
      'youtube',
      'JioSaavn failed for https://media.example.test/audio?sig=temporary',
      <String, Object?>{
        'api_key': 'do-not-export',
        'cookie': 'session=do-not-export-either',
        'source': 'jioSaavn',
      },
    );

    final entry = AppLog.snapshot().single;
    final formatted = entry.format();
    expect(entry.category, 'Source B');
    expect(entry.message, contains('Source A'));
    expect(formatted, contains('[network address redacted]'));
    expect(formatted, contains('api_key: [redacted]'));
    expect(formatted, contains('cookie: [redacted]'));
    expect(formatted, isNot(contains('do-not-export-either')));
    expect(formatted, isNot(contains('youtube')));
    expect(formatted, isNot(contains('jioSaavn')));
    expect(
      sanitizeLogText('package:youtube_explode_dart'),
      'package:Source B',
    );
    expect(formatted, isNot(contains('do-not-export')));
    expect(formatted, isNot(contains('temporary')));
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
