import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muzic/models/song_model.dart';
import 'package:muzic/services/library_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('keeps downloads visible when their offline file is missing', () async {
    final directory =
        await Directory.systemTemp.createTemp('muzic-library-test-');
    Hive.init(directory.path);
    final library = LibraryService(initializeHive: () async {});
    await library.init();

    try {
      final missingPath = p.join(directory.path, 'removed-track.m4a');
      final song = SongModel(
        id: 'youtube:video1234567',
        sourceId: 'video1234567',
        title: 'Saved track',
        artist: 'Example artist',
        source: SongSource.youtube,
        localPath: missingPath,
      );
      await library.saveDownload(song);

      expect(library.downloadedSongs, hasLength(1));
      expect(library.hasUnavailableDownload(song.id), isTrue);
      expect(library.isDownloaded(song.id), isFalse);

      await library.markDownloadUnavailable(song.id);

      expect(library.downloadedSongs, hasLength(1));
      expect(library.downloadedSongs.single.localPath, isNull);
      expect(library.hasUnavailableDownload(song.id), isTrue);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
