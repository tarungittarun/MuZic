import 'package:flutter_test/flutter_test.dart';
import 'package:muzic/models/song_model.dart';
import 'package:muzic/services/playback_recovery.dart';

SongModel _song(SongSource source, {String? streamUrl}) => SongModel(
      id: 'test-track',
      sourceId: 'test-track',
      title: 'Test Track',
      artist: 'Test Artist',
      source: source,
      streamUrl: streamUrl,
    );

void main() {
  test('lowers Source A quality, refreshes the URL, then changes source', () {
    final song = _song(
      SongSource.jioSaavn,
      streamUrl: 'https://media.example/track_320.mp4',
    );

    expect(
      nextPlaybackRecoveryAction(song: song, attempts: <String>{}),
      PlaybackRecoveryAction.lowerSourceAQuality,
    );
    expect(
      nextPlaybackRecoveryAction(
        song: song,
        attempts: <String>{'quality'},
      ),
      PlaybackRecoveryAction.refreshSourceA,
    );
    expect(
      nextPlaybackRecoveryAction(
        song: song,
        attempts: <String>{'quality', 'source-a-refresh'},
      ),
      PlaybackRecoveryAction.alternateSource,
    );
  });

  test('refreshes a regular Source A URL before changing source', () {
    final song = _song(
      SongSource.jioSaavn,
      streamUrl: 'https://media.example/track_96.mp4',
    );

    expect(
      nextPlaybackRecoveryAction(song: song, attempts: <String>{}),
      PlaybackRecoveryAction.refreshSourceA,
    );
  });

  test('tries lower Source B bitrate, then one alternate source', () {
    final song = _song(
      SongSource.youtube,
      streamUrl: 'https://media.example/audio',
    );

    expect(
      nextPlaybackRecoveryAction(song: song, attempts: <String>{}),
      PlaybackRecoveryAction.lowerSourceBBitrate,
    );
    expect(
      nextPlaybackRecoveryAction(
        song: song,
        attempts: <String>{'youtube-low'},
      ),
      PlaybackRecoveryAction.alternateSource,
    );
    expect(
      nextPlaybackRecoveryAction(
        song: song,
        attempts: <String>{'youtube-low', 'youtube'},
      ),
      PlaybackRecoveryAction.stop,
    );
  });

  test('does not cross-fallback local files or radio streams', () {
    for (final source in <SongSource>[SongSource.local, SongSource.radio]) {
      expect(
        nextPlaybackRecoveryAction(
          song: _song(source),
          attempts: <String>{},
        ),
        PlaybackRecoveryAction.stop,
      );
    }
  });
}
