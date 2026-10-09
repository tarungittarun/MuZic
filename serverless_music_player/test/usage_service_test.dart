import 'dart:io';

import 'package:auralis_player/models/song_model.dart';
import 'package:auralis_player/services/usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('persists local activity, serializes counters, and clears history', () async {
    final directory = await Directory.systemTemp.createTemp('auralis-usage-test-');
    Hive.init(directory.path);
    final usage = UsageService();
    await usage.init();

    try {
      await Future.wait(<Future<void>>[
        for (var index = 0; index < 20; index++)
          usage.recordSearch(
            query: 'ambient music',
            source: 'automatic',
            resultCount: 6,
          ),
      ]);
      const song = SongModel(
        id: 'saavn:calm-night',
        sourceId: 'calm-night',
        title: 'Calm Night',
        artist: 'Example Artist',
        source: SongSource.jioSaavn,
      );
      await usage.recordSongEvent('play', song);
      await usage.recordSongEvent('favorite_added', song);
      await usage.recordSongEvent('download', song);
      await usage.addListeningTime(const Duration(minutes: 3, seconds: 12));

      expect(usage.searches, 20);
      expect(usage.playStarts, 1);
      expect(usage.favoritesAdded, 1);
      expect(usage.downloads, 1);
      expect(usage.listeningTime, const Duration(minutes: 3, seconds: 12));
      expect(usage.topSearches.first.query, 'ambient music');
      expect(usage.topSearches.first.searches, 20);
      expect(usage.topTracks.single.title, 'Calm Night');
      expect(usage.recentEvents, isNotEmpty);

      await usage.clear();
      expect(usage.searches, 0);
      expect(usage.playStarts, 0);
      expect(usage.listeningTime, Duration.zero);
      expect(usage.recentEvents, isEmpty);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
