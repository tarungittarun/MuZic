import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/audio_quality.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/services/lossless_radio_service.dart';

SongModel _song({
  required SongSource source,
  String? streamUrl,
  String? localPath,
}) {
  return SongModel(
    id: '${source.name}:1',
    sourceId: '1',
    title: 'Track',
    artist: 'Artist',
    source: source,
    streamUrl: streamUrl,
    localPath: localPath,
  );
}

void main() {
  group('describeAudio', () {
    test('detects JioSaavn 320 kbps streams', () {
      final info = describeAudio(_song(
        source: SongSource.jioSaavn,
        streamUrl: 'https://aac.saavncdn.com/abc/def_320.mp4',
      ));
      expect(info.label, 'AAC 320 kbps');
      expect(info.isLossless, isFalse);
      expect(info.detail, contains('Source A'));
    });

    test('detects JioSaavn 96 kbps streams', () {
      final info = describeAudio(_song(
        source: SongSource.jioSaavn,
        streamUrl: 'https://aac.saavncdn.com/abc/def_96.mp4',
      ));
      expect(info.label, 'AAC 96 kbps');
    });

    test('identifies YouTube webm as lossy Opus', () {
      final info = describeAudio(_song(
        source: SongSource.youtube,
        streamUrl: 'https://rr1.googlevideo.com/videoplayback?mime=audio%2Fwebm',
      ));
      expect(info.detail, contains('Source B'));
      expect(info.isLossless, isFalse);
    });

    test('marks live radio as lossless FLAC', () {
      final info = describeAudio(_song(
        source: SongSource.radio,
        streamUrl: 'https://stream.radioparadise.com/flac',
      ));
      expect(info.isLossless, isTrue);
      expect(info.label, contains('FLAC'));
    });

    test('marks local FLAC files as lossless', () {
      final info = describeAudio(_song(
        source: SongSource.local,
        localPath: '/data/music/track.flac',
      ));
      expect(info.isLossless, isTrue);
      expect(info.label, contains('FLAC'));
    });

    test('marks local MP3 files as lossy', () {
      final info = describeAudio(_song(
        source: SongSource.local,
        localPath: '/data/music/track.mp3',
      ));
      expect(info.isLossless, isFalse);
      expect(info.label, contains('MP3'));
    });

    test('never throws for unresolved remote songs', () {
      final info = describeAudio(_song(source: SongSource.youtube));
      expect(info.label, isNotEmpty);
    });
  });

  group('LosslessRadioService', () {
    test('exposes unique https stations', () {
      expect(LosslessRadioService.stations, isNotEmpty);
      final ids = LosslessRadioService.stations.map((s) => s.id).toSet();
      expect(ids.length, LosslessRadioService.stations.length);
      for (final station in LosslessRadioService.stations) {
        expect(station.streamUrl, startsWith('https://'));
        expect(station.name, isNotEmpty);
      }
    });

    test('builds playable live radio songs', () {
      final song = LosslessRadioService.stations.first.toSong();
      expect(song.source, SongSource.radio);
      expect(song.isLiveStream, isTrue);
      expect(song.id, startsWith('radio:'));
      expect(song.streamUrl, isNotNull);
      expect(describeAudio(song).isLossless, isTrue);
    });
  });

  test('source enum round-trips through maps', () {
    for (final source in SongSource.values) {
      final song = SongModel(
        id: '${source.name}:9',
        sourceId: '9',
        title: 'T',
        artist: 'A',
        source: source,
      );
      expect(SongModel.fromMap(song.toMap()).source, source);
    }
  });
}
