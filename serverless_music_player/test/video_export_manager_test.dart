import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/lyrics_model.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/services/download_service.dart';
import 'package:music_player/services/video_export_manager.dart';
import 'package:music_player/services/video_export_service.dart';

class _FakeVideoExportService extends VideoExportService {
  _FakeVideoExportService() : super();

  final StreamController<double> progressController =
      StreamController<double>.broadcast(sync: true);
  bool cancelled = false;
  int exportCount = 0;
  String? lastOutputFolderUri;

  @override
  Stream<double> get progress => progressController.stream;

  @override
  Future<VideoExportResult> export({
    required SongModel song,
    required String audioPath,
    required LyricsModel? lyrics,
    String? outputFolderUri,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    exportCount++;
    lastOutputFolderUri = outputFolderUri;
    progressController.add(0.5);
    onProgress?.call(0.5);
    return const VideoExportResult(path: 'content://video/result', shared: true);
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

const _song = SongModel(
  id: 'track-1',
  sourceId: 'track-1',
  title: 'Example Track',
  artist: 'Example Artist',
  source: SongSource.youtube,
);

void main() {
  group('VideoExportManager', () {
    test('keeps one progress lifecycle and cleans temporary audio', () async {
      final service = _FakeVideoExportService();
      final manager = VideoExportManager(service: service);
      addTearDown(() async {
        manager.dispose();
        await service.progressController.close();
      });
      String? cleanedPath;

      final result = await manager.start(
        song: _song,
        outputFolderUri: 'content://downloads/tree/muzic',
        prepareAudio: (onProgress, isCancelled) async {
          onProgress(0.5);
          return '/tmp/example-audio.m4a';
        },
        loadLyrics: () async => null,
        cleanupAudio: (path) async {
          cleanedPath = path;
        },
      );

      expect(result?.path, 'content://video/result');
      expect(service.lastOutputFolderUri, 'content://downloads/tree/muzic');
      expect(manager.state, VideoExportState.done);
      expect(manager.percent, 100);
      expect(cleanedPath, '/tmp/example-audio.m4a');
      expect(service.cancelled, isFalse);
    });

    test('keeps the default output when no downloads folder is selected', () async {
      final service = _FakeVideoExportService();
      final manager = VideoExportManager(service: service);
      addTearDown(() async {
        manager.dispose();
        await service.progressController.close();
      });

      await manager.start(
        song: _song,
        prepareAudio: (onProgress, isCancelled) async => '/tmp/example-audio.m4a',
        loadLyrics: () async => null,
      );

      expect(service.lastOutputFolderUri, isNull);
    });

    test('cancels audio preparation without starting the encoder', () async {
      final service = _FakeVideoExportService();
      final manager = VideoExportManager(service: service);
      addTearDown(() async {
        manager.dispose();
        await service.progressController.close();
      });
      final preparation = Completer<void>();
      final preparationStarted = Completer<void>();

      final resultFuture = manager.start(
        song: _song,
        prepareAudio: (onProgress, isCancelled) async {
          preparationStarted.complete();
          await preparation.future;
          if (isCancelled()) throw const DownloadCancelledException();
          return '/tmp/example-audio.m4a';
        },
        loadLyrics: () async => null,
        cancelPreparation: () async {
          if (!preparation.isCompleted) preparation.complete();
        },
      );
      expect(manager.isBusy, isTrue);
      await preparationStarted.future;

      await manager.cancel();
      final result = await resultFuture;

      expect(result, isNull);
      expect(manager.state, VideoExportState.idle);
      expect(service.cancelled, isFalse);
    });

    test('cancels lyric lookup promptly and cleans prepared audio', () async {
      final service = _FakeVideoExportService();
      final manager = VideoExportManager(service: service);
      addTearDown(() async {
        manager.dispose();
        await service.progressController.close();
      });
      final lyricsStarted = Completer<void>();
      final lyrics = Completer<LyricsModel?>();
      String? cleanedPath;

      final resultFuture = manager.start(
        song: _song,
        prepareAudio: (onProgress, isCancelled) async {
          onProgress(0);
          if (isCancelled()) throw const DownloadCancelledException();
          return '/tmp/example-audio.m4a';
        },
        loadLyrics: () {
          lyricsStarted.complete();
          return lyrics.future;
        },
        cancelPreparation: () async {},
        cleanupAudio: (path) async {
          cleanedPath = path;
        },
      );
      await lyricsStarted.future;

      await manager.cancel();
      final result = await resultFuture;

      expect(result, isNull);
      expect(manager.state, VideoExportState.idle);
      expect(service.exportCount, 0);
      expect(cleanedPath, '/tmp/example-audio.m4a');
    });
  });
}
