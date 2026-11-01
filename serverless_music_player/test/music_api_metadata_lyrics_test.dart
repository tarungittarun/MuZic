import 'dart:convert';

import 'package:muzic/models/lyrics_model.dart';
import 'package:muzic/models/song_model.dart';
import 'package:muzic/services/music_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('YouTube link parsing', () {
    test('extracts the exact video from watch, short, Shorts, and embed URLs', () {
      const videoId = 'dQw4w9WgXcQ';
      expect(
        MusicApiService.youtubeVideoIdFromUrl(
          'https://www.youtube.com/watch?v=$videoId&list=PL123',
        ),
        videoId,
      );
      expect(
        MusicApiService.youtubeVideoIdFromUrl('youtu.be/$videoId?t=23'),
        videoId,
      );
      expect(
        MusicApiService.youtubeVideoIdFromUrl(
          'https://m.youtube.com/shorts/$videoId',
        ),
        videoId,
      );
      expect(
        MusicApiService.youtubeVideoIdFromUrl(
          'https://www.youtube-nocookie.com/embed/$videoId',
        ),
        videoId,
      );
    });

    test('rejects non-video links and lookalike hosts', () {
      expect(
        MusicApiService.youtubeVideoIdFromUrl(
          'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ',
        ),
        isNull,
      );
      expect(
        MusicApiService.youtubeVideoIdFromUrl(
          'https://www.youtube.com/playlist?list=PL123',
        ),
        isNull,
      );
      expect(
        MusicApiService.youtubeVideoIdFromUrl('https://youtu.be/short'),
        isNull,
      );
    });
  });

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

  group('MusicApiService search updates', () {
    test('publishes catalogue results to the caller as soon as they arrive', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(<String, dynamic>{
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'search-song',
                  'title': 'Search Song',
                  'primary_artists': 'Example Artist',
                  'more_info': <String, dynamic>{'duration': '180'},
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          ));
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      final updates = <List<SongModel>>[];

      final songs = await api.search(
        'Search Song',
        source: SearchSource.jioSaavn,
        limit: 10,
        onUpdate: updates.add,
      );

      expect(songs, hasLength(1));
      expect(updates, hasLength(1));
      expect(updates.single.single.id, songs.single.id);
    });
  });

  group('MusicApiService artist search', () {
    test('parses artist results for the artist library', () async {
      Uri? requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'results': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'artist-1',
                'title': 'Example Artist',
                'subtitle': 'Artist',
                'image': 'https://example.test/artist-150.jpg',
              },
              <String, dynamic>{
                'id': '',
                'title': 'Ignore incomplete rows',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);

      final artists = await api.searchArtists('Example Artist');

      expect(requestedUri?.queryParameters['__call'], 'search.getArtistResults');
      expect(artists, hasLength(1));
      expect(artists.single.id, 'artist-1');
      expect(artists.single.name, 'Example Artist');
      expect(artists.single.imageUrl, contains('artist'));
    });
  });

  group('MusicApiService stream refresh', () {
    test(
      'refreshes a Source A URL by ID and downgrades an unresponsive 320 link',
      () async {
        const encryptedUrl =
            'iPPGVzyogeiPwpro65A0eUaQggN+8+J4mteJdeaEeFiCL4nTGWnI3F16SIjtZBIxsc7WJNlKm0HtZ754aGgzDIPzFaL/aK97';
        var requestCount = 0;
        final client = MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'track-123',
                  'title': 'Track title',
                  'primary_artists': 'Main artist',
                  'more_info': <String, dynamic>{
                    'encrypted_media_url': encryptedUrl,
                    '320kbps': 'true',
                  },
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        });
        final api = MusicApiService(httpClient: client);
        addTearDown(api.dispose);
        const song = SongModel(
          id: 'saavn:track-123',
          sourceId: 'track-123',
          title: 'Track title',
          artist: 'Main artist',
          source: SongSource.jioSaavn,
        );

        final refreshed = await api.refreshSourceAStream(
          song,
          preferLowerBitrate: true,
        );

        expect(refreshed, endsWith('_96.mp4'));
        expect(requestCount, 1);
      },
    );
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

    test('retries lyrics after an empty result instead of caching a miss', () async {
      var exactCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/get') {
          exactCalls++;
          if (exactCalls == 1) return http.Response('not found', 404);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'instrumental': false,
              'plainLyrics': 'Lyrics appeared on retry',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      const song = SongModel(
        id: 'youtube:retry-video',
        sourceId: 'retry-video',
        title: 'Retryable Song (Official Audio)',
        artist: 'Example Artist',
        source: SongSource.youtube,
      );

      final first = await api.fetchLyrics(song);
      final second = await api.fetchLyrics(song);

      expect(first.isEmpty, isTrue);
      expect(second.plainLyrics, 'Lyrics appeared on retry');
      expect(exactCalls, 2);
    });

    test('returns fast when primary lyrics are already synced', () async {
      var lrclibSearchCount = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'www.jiosaavn.com') {
          return http.Response(
            jsonEncode(<String, dynamic>{'lyrics': 'JioSaavn lyric line'}),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/search') {
          lrclibSearchCount++;
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'trackName': 'Fast Song',
                'artistName': 'Fast Artist',
                'plainLyrics': 'Extra catalogue lyric',
              },
            ]),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'instrumental': false,
            'plainLyrics': 'Fast line',
            'syncedLyrics': '[00:01.00]Fast line',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      const song = SongModel(
        id: 'saavn:fast-song',
        sourceId: 'fast-song',
        title: 'Fast Song',
        artist: 'Fast Artist',
        source: SongSource.jioSaavn,
        durationMs: 180000,
      );

      final bundle = await api.fetchLyricsVariants(song);

      expect(bundle.variants.where((variant) => !variant.isEmpty), isNotEmpty);
      expect(bundle.variants.any((variant) => variant.hasSynced), isTrue);
      expect(
        bundle.variants.any((variant) => variant.plainLyrics.contains('JioSaavn')),
        isTrue,
      );
      // A synced primary result does not trigger a redundant catalogue
      // request; Source A is fetched concurrently as a separate variant.
      expect(lrclibSearchCount, 0);
    });

    test('finds Source A lyrics for a YouTube result', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'www.jiosaavn.com') {
          if (request.url.queryParameters['__call'] == 'search.getResults') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'results': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'catalogue-track-1',
                    'title': 'Regional Song',
                    'primary_artists': 'Example Artist',
                    'more_info': <String, dynamic>{'duration': '220'},
                  },
                ],
              }),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{'lyrics': 'A regional lyric line'}),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);
      const song = SongModel(
        id: 'youtube:video1234567',
        sourceId: 'video1234567',
        title: 'Regional Song (Official Video)',
        artist: 'Example Artist',
        source: SongSource.youtube,
        durationMs: 220000,
      );

      final updates = <LyricsBundle>[];
      final bundle = await api.fetchLyricsVariants(song, onUpdate: updates.add);

      expect(
        bundle.variants.any((variant) =>
            variant.source == 'jiosaavn' &&
            variant.plainLyrics == 'A regional lyric line'),
        isTrue,
      );
      expect(
        updates.any((update) => update.variants.any(
              (variant) => variant.plainLyrics == 'A regional lyric line',
            )),
        isTrue,
      );
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

      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
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
        id: 'youtube:target-video',
        sourceId: 'target-video',
        title: 'Target Song (Official Video)',
        artist: 'Example Artist',
        source: SongSource.youtube,
        durationMs: 200000,
      );

      final lyrics = await api.fetchLyrics(song);
      expect(requestedPaths, <String>['/api/get', '/api/search']);
      expect(lyrics.plainLyrics, 'The matching lyrics');
    });
  });
}
