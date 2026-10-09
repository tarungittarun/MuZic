import 'dart:convert';

import 'package:auralis_player/models/song_model.dart';
import 'package:auralis_player/services/music_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('MusicApiService metadata parsing', () {
    test('parses optional JioSaavn metadata defensively', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(<String, dynamic>{
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'track-123',
                  'title': 'Track title',
                  'primary_artists': 'Main artist',
                  'album': 'Album title',
                  'year': '2024',
                  'image': 'https://example.test/150x150.jpg',
                  'perma_url': 'https://www.jiosaavn.com/song/example',
                  'play_count': '12345',
                  'more_info': <String, dynamic>{
                    'duration': '245',
                    'release_date': '2024-03-12',
                    'language': 'English',
                    'label': 'Example Records',
                    'copyright_text': 'Copyright holder',
                    'music': 'Composer name',
                    'has_lyrics': 'true',
                    'explicit_content': 'false',
                    'artists': <String, dynamic>{
                      'featured': <Map<String, String>>[
                        <String, String>{'name': 'Guest artist'},
                      ],
                    },
                  },
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          ));
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);

      final songs = await api.searchJioSaavn('track title', limit: 5);
      expect(songs, hasLength(1));
      final song = songs.single;
      expect(song.artist, 'Main artist');
      expect(song.album, 'Album title');
      expect(song.duration?.inSeconds, 245);
      expect(song.releaseDate, '2024-03-12');
      expect(song.language, 'English');
      expect(song.label, 'Example Records');
      expect(song.copyright, 'Copyright holder');
      expect(song.composer, 'Composer name');
      expect(song.featuredArtists, <String>['Guest artist']);
      expect(song.playCount, 12345);
      expect(song.hasLyrics, isTrue);
      expect(song.isExplicit, isFalse);
      expect(song.sourceUrl, 'https://www.jiosaavn.com/song/example');
    });
  });

  group('MusicApiService lyrics', () {
    test('uses exact LRCLIB match, parses synced lines, and caches it', () async {
      var requestCount = 0;
      Uri? requestUri;
      final client = MockClient((request) async {
        requestCount++;
        requestUri = request.url;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'instrumental': false,
            'plainLyrics': 'First line\nSecond line',
            'syncedLyrics': '[00:01.20]First line\n[00:02.50]Second line',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      const song = SongModel(
        id: 'saavn:blinding-lights',
        sourceId: 'blinding-lights',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        source: SongSource.jioSaavn,
        durationMs: 200000,
      );

      final lyrics = await api.fetchLyrics(song);
      final cachedLyrics = await api.fetchLyrics(song);
      expect(requestCount, 1);
      expect(requestUri?.host, 'lrclib.net');
      expect(requestUri?.path, '/api/get');
      expect(requestUri?.queryParameters['duration'], '200');
      expect(requestUri?.queryParameters['album_name'], 'After Hours');
      expect(lyrics.plainLyrics, 'First line\nSecond line');
      expect(lyrics.syncedLines, hasLength(2));
      expect(lyrics.syncedLines.first.time, const Duration(seconds: 1, milliseconds: 200));
      expect(cachedLyrics.plainLyrics, lyrics.plainLyrics);
    });

    test('honors LRCLIB Retry-After before a later request', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('slow down', 429, headers: const <String, String>{'Retry-After': '1'});
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'instrumental': false,
            'plainLyrics': 'Available after the wait',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      const song = SongModel(
        id: 'saavn:retry-track',
        sourceId: 'retry-track',
        title: 'Retry Track',
        artist: 'Retry Artist',
        source: SongSource.jioSaavn,
      );

      await expectLater(api.fetchLyrics(song), throwsA(isA<http.ClientException>()));
      final stopwatch = Stopwatch()..start();
      final lyrics = await api.fetchLyrics(song);
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqual(const Duration(milliseconds: 900)));
      expect(lyrics.plainLyrics, 'Available after the wait');
      expect(requestCount, 2);
    });

    test('falls back to title-and-artist search after an exact miss', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'trackName': 'Unrelated Song',
              'artistName': 'Example Artist',
              'duration': 200,
              'plainLyrics': 'Do not select these lyrics',
            },
            <String, dynamic>{
              'trackName': 'Target Song',
              'artistName': 'Example Artist',
              'duration': 201,
              'plainLyrics': 'The matching lyrics',
            },
          ]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      const song = SongModel(
        id: 'saavn:target-song',
        sourceId: 'target-song',
        title: 'Target Song',
        artist: 'Example Artist',
        source: SongSource.jioSaavn,
        durationMs: 200000,
      );

      final lyrics = await api.fetchLyrics(song);
      expect(requestedPaths, <String>['/api/get', '/api/search']);
      expect(lyrics.plainLyrics, 'The matching lyrics');
    });
  });
}
