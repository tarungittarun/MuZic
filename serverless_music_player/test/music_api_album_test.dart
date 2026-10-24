import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_player/services/music_api_service.dart';

Map<String, dynamic> _track(String id, String title, String album) =>
    <String, dynamic>{
      'id': id,
      'title': title,
      'primary_artists': 'Example Artist',
      'album': album,
      'image': 'https://example.test/album.jpg',
      'more_info': <String, dynamic>{'duration': '210'},
    };

void main() {
  group('MusicApiService album tracks', () {
    test('finds tracks through nested album response wrappers', () async {
      Uri? requestUri;
      final client = MockClient((request) async {
        requestUri = request.url;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'data': <String, dynamic>{
              'album': <String, dynamic>{
                'id': 'album-1',
                'songs': <String, dynamic>{
                  'data': <Map<String, dynamic>>[
                    _track('track-1', 'Tum Hi Ho', 'Aashiqui 2'),
                  ],
                },
              },
            },
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);

      final songs = await api.fetchAlbumSongs(
        'album-1',
        albumTitle: 'Aashiqui 2',
        albumArtist: 'Example Artist',
      );

      expect(requestUri?.queryParameters['__call'], 'content.getAlbumDetails');
      expect(songs, hasLength(1));
      expect(songs.single.title, 'Tum Hi Ho');
      expect(songs.single.album, 'Aashiqui 2');
    });

    test('recovers album tracks by title when details have no songs', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        final call = request.url.queryParameters['__call'] ?? '';
        calls.add(call);
        if (call == 'content.getAlbumDetails') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'album': <String, dynamic>{'id': 'album-2'},
                'songs': <dynamic>[],
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'results': <Map<String, dynamic>>[
              _track('track-2', 'Tum Hi Ho', 'Aashiqui 2'),
              _track('track-other-album', 'Different Song', 'Aashiqui'),
              _track('track-other', 'Other Song', 'Another Album'),
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final api = MusicApiService(httpClient: client);
      addTearDown(api.dispose);

      final songs = await api.fetchAlbumSongs(
        'album-2',
        albumTitle: 'Aashiqui 2',
        albumArtist: 'Example Artist',
      );

      expect(calls, <String>['content.getAlbumDetails', 'search.getResults']);
      expect(songs, hasLength(1));
      expect(songs.single.id, 'saavn:track-2');
    });
  });
}
