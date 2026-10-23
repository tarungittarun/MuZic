import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/audio_quality.dart';
import 'package:music_player/models/lyrics_model.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/screens/diagnostics_screen.dart';

void main() {
  test('quality details use the app-owned source labels', () {
    const sourceA = SongModel(
      id: 'a',
      sourceId: 'a',
      title: 'Track',
      artist: 'Artist',
      source: SongSource.jioSaavn,
      streamUrl: 'https://audio.example/track_320.mp4',
    );
    const sourceB = SongModel(
      id: 'b',
      sourceId: 'b',
      title: 'Track',
      artist: 'Artist',
      source: SongSource.youtube,
      streamUrl: 'https://media.example/track?mime=audio%2Fwebm',
    );

    expect(describeAudio(sourceA).detail, 'Lossy · Source A');
    expect(describeAudio(sourceB).detail, 'Lossy · Source B');
  });

  test('lyrics labels do not expose the underlying provider', () {
    const lyrics = LyricsModel(
      language: 'hindi',
      languageLabel: 'Hindi',
      source: 'jiosaavn',
      plainLyrics: 'line',
    );
    expect(lyrics.displayLabel, 'Hindi · Plain · Source A');
  });

  test('diagnostic screen neutralizes provider and device-brand names', () {
    final text = neutralizeProviderNames(
      'YouTube JioSaavn LRCLIB Spotify RadioParadise Radio Paradise '
      'Motorola Android Google Apple Chrome One UI '
      'https://aac.saavncdn.com/track.mp4 '
      'https://rr1.googlevideo.com/stream',
    );

    expect(text, contains('Source B'));
    expect(text, contains('Source A'));
    expect(text, contains('lyrics source'));
    expect(text, contains('radio source'));
    expect(text, contains('device'));
    expect(text, contains('system'));
    for (final name in <String>[
      'YouTube',
      'JioSaavn',
      'LRCLIB',
      'Spotify',
      'RadioParadise',
      'Radio Paradise',
      'Motorola',
      'Android',
      'Google',
      'Apple',
      'Chrome',
      'One UI',
      'saavncdn.com',
      'googlevideo.com',
      'https://',
    ]) {
      expect(text, isNot(contains(name)));
    }
  });
}
