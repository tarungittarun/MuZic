import 'package:auralis_player/models/song_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips optional provider metadata', () {
    const song = SongModel(
      id: 'youtube:abc123',
      sourceId: 'abc123',
      title: 'Example track',
      artist: 'Lead artist',
      album: 'Example album',
      artworkUrl: 'https://example.test/cover.jpg',
      source: SongSource.youtube,
      durationMs: 187000,
      releaseDate: '2024-09-03',
      language: 'English',
      label: 'Example Records',
      copyright: 'Copyright holder',
      composer: 'Composer',
      featuredArtists: <String>['Guest artist'],
      playCount: 4200,
      hasLyrics: true,
      isExplicit: false,
      sourceUrl: 'https://youtu.be/abc123',
    );

    final restored = SongModel.fromMap(song.toMap());
    expect(restored.id, song.id);
    expect(restored.source, SongSource.youtube);
    expect(restored.duration, const Duration(minutes: 3, seconds: 7));
    expect(restored.releaseDate, song.releaseDate);
    expect(restored.language, song.language);
    expect(restored.label, song.label);
    expect(restored.copyright, song.copyright);
    expect(restored.composer, song.composer);
    expect(restored.featuredArtists, song.featuredArtists);
    expect(restored.playCount, song.playCount);
    expect(restored.hasLyrics, isTrue);
    expect(restored.isExplicit, isFalse);
    expect(restored.sourceUrl, song.sourceUrl);
  });

  test('loads older saved maps without optional fields', () {
    final song = SongModel.fromMap(<String, dynamic>{
      'id': 'saavn:legacy',
      'sourceId': 'legacy',
      'title': 'Legacy track',
      'artist': 'Legacy artist',
      'source': 'jioSaavn',
    });

    expect(song.title, 'Legacy track');
    expect(song.duration, isNull);
    expect(song.releaseDate, isNull);
    expect(song.featuredArtists, isEmpty);
    expect(song.hasLyrics, isNull);
  });
}
