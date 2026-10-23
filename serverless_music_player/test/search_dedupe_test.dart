import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/services/music_api_service.dart';

SongModel copy(String id, String artist, String album) => SongModel(
      id: id,
      sourceId: id,
      title: 'Apna Bana Le',
      artist: artist,
      album: album,
      source: SongSource.jioSaavn,
      durationMs: 261000,
      streamUrl: 'https://example.test/$id.m4a',
      artworkUrl: 'https://example.test/$id.jpg',
    );

void main() {
  test('search collapses repeated copies of the same recording', () {
    final results = MusicApiService.dedupeSearchResults(<SongModel>[
      copy('one', 'Sachin-Jigar, Arijit Singh, Amitabh Bhattacharya', 'Bhediya'),
      copy('two', 'Amitabh Bhattacharya, Sachin-Jigar, Arijit Singh', 'Bollywood Years'),
      copy('three', 'Sachin-Jigar, Arijit Singh, Amitabh Bhattacharya', 'Love Songs'),
      copy('four', 'Arijit Singh, Sachin-Jigar', 'Bhediya (From "Bhediya")')
          .copyWith(title: 'Apna Bana Le (From "Bhediya")'),
      const SongModel(
        id: 'different',
        sourceId: 'different',
        title: 'Apna Bana Le',
        artist: 'Another Singer',
        album: 'Different recording',
        source: SongSource.jioSaavn,
        durationMs: 198000,
        streamUrl: 'https://example.test/different.m4a',
      ),
    ]);

    expect(results, hasLength(2));
    expect(results.first.title, 'Apna Bana Le');
    expect(results.last.id, 'different');
  });
}
