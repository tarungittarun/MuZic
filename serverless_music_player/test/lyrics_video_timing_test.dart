import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/lyrics_model.dart';
import 'package:music_player/services/lyrics_video_timing.dart';

void main() {
  group('lyrics video timing fallback', () {
    test('spaces plain caption lines across the track duration', () {
      const plain = LyricsModel(
        plainLyrics: 'First line\n\nSecond line\nThird line',
      );

      final videoLyrics = estimateLyricsTimingForVideo(
        plain,
        duration: const Duration(seconds: 90),
      );

      expect(videoLyrics, isNotNull);
      expect(videoLyrics!.hasSynced, isTrue);
      expect(videoLyrics.syncedLines.map((line) => line.text), <String>[
        'First line',
        'Second line',
        'Third line',
      ]);
      expect(videoLyrics.syncedLines.first.time, Duration.zero);
      expect(
        videoLyrics.syncedLines.last.time,
        const Duration(seconds: 87, milliseconds: 500),
      );
      expect(plain.hasSynced, isFalse);
    });

    test('leaves existing timed lyrics unchanged', () {
      const synced = LyricsModel(
        syncedLines: <LyricLine>[
          LyricLine(time: Duration(seconds: 3), text: 'Timed line'),
        ],
      );

      expect(
        estimateLyricsTimingForVideo(synced, duration: const Duration(minutes: 3)),
        same(synced),
      );
    });
  });
}
