import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/services/recommendation_engine.dart';

SongModel song(
  String id,
  String title,
  String artist, {
  String language = 'hindi',
  String album = '',
  int? playCount,
}) {
  return SongModel(
    id: id,
    sourceId: id,
    title: title,
    artist: artist,
    album: album,
    source: SongSource.jioSaavn,
    durationMs: 210000,
    language: language,
    playCount: playCount,
    streamUrl: 'https://example.test/$id.mp4',
    artworkUrl: 'https://example.test/$id.jpg',
  );
}

RecommendationCandidate candidate(SongModel value, [String lane = 'artist']) {
  return RecommendationCandidate(song: value, lane: lane);
}

void main() {
  group('RecommendationEngine', () {
    final seed = song('seed', 'Gehra Hua', 'Arijit Singh');

    test('canonical title removes alternate-version decorations', () {
      expect(
        RecommendationEngine.canonicalTitleKey('Song Name (feat. Guest)'),
        'song name',
      );
      expect(
        RecommendationEngine.canonicalTitleKey('Song Name - Remastered 2024'),
        'song name',
      );
      expect(
        RecommendationEngine.canonicalTitleKey('Song Name [Official Audio]'),
        'song name',
      );
    });

    test('does not recommend the seed, alternate versions, queue or recents',
        () {
      final ranked = RecommendationEngine.rank(
        candidates: <RecommendationCandidate>[
          candidate(seed),
          candidate(song('alt', 'Gehra Hua (Arijit Version)', 'Someone Else')),
          candidate(song('queued', 'Already Queued', 'Artist One')),
          candidate(song('recent', 'Heard Yesterday', 'Artist Two')),
          candidate(song('old-rec', 'Shown Last Time', 'Artist Three')),
          candidate(song('fresh', 'Fresh Discovery', 'Artist Four')),
        ],
        seed: seed,
        excludedIds: const <String>{'queued'},
        excludedTitleKeys: <String>{
          RecommendationEngine.canonicalTitleKey('Already Queued'),
        },
        recentlyPlayedIds: const <String>{'recent'},
        recentTitleKeys: <String>{
          RecommendationEngine.canonicalTitleKey('Heard Yesterday'),
        },
        previouslyRecommendedIds: const <String>{'old-rec'},
        artistAffinity: const <String, double>{},
        preferredLanguages: const <String>{'hindi'},
      );

      expect(ranked.map((item) => item.song.id), <String>['fresh']);
    });

    test('keeps the radio diverse instead of filling it with one artist', () {
      final candidates = <RecommendationCandidate>[
        for (var index = 0; index < 6; index++)
          candidate(song('a$index', 'Arijit Song $index', 'Arijit Singh')),
        candidate(song('b1', 'Discovery One', 'Anuv Jain')),
        candidate(song('c1', 'Discovery Two', 'Pritam')),
        candidate(song('d1', 'Discovery Three', 'Shreya Ghoshal')),
        candidate(song('e1', 'Discovery Four', 'Vishal Mishra')),
      ];

      final ranked = RecommendationEngine.rank(
        candidates: candidates,
        seed: seed,
        excludedIds: const <String>{},
        excludedTitleKeys: const <String>{},
        recentlyPlayedIds: const <String>{},
        recentTitleKeys: const <String>{},
        previouslyRecommendedIds: const <String>{},
        artistAffinity: const <String, double>{'arijit singh': 20},
        preferredLanguages: const <String>{'hindi'},
        limit: 6,
      );

      final artists = ranked
          .map((item) => RecommendationEngine.primaryArtistKey(item.song))
          .toList();
      expect(ranked, hasLength(6));
      expect(artists.where((artist) => artist == 'arijit singh').length,
          lessThanOrEqualTo(2));
      expect(artists.toSet().length, greaterThanOrEqualTo(5));
    });

    test('familiar and discovery mixes change the leading pick', () {
      final familiarSong = song('familiar', 'Known Artist Pick', 'Anuv Jain');
      final discoverySong = song(
        'discovery',
        'Chart Pick',
        'New Voice',
        playCount: 900000,
      );
      final candidates = <RecommendationCandidate>[
        candidate(familiarSong, 'artist'),
        candidate(discoverySong, 'trending'),
      ];
      final affinity = <String, double>{'anuv jain': 13};

      List<RankedRecommendation> run(String style) {
        return RecommendationEngine.rank(
          candidates: candidates,
          seed: seed,
          excludedIds: const <String>{},
          excludedTitleKeys: const <String>{},
          recentlyPlayedIds: const <String>{},
          recentTitleKeys: const <String>{},
          previouslyRecommendedIds: const <String>{},
          artistAffinity: affinity,
          preferredLanguages: const <String>{'hindi'},
          style: style,
        );
      }

      expect(run('familiar').first.song.id, 'familiar');
      expect(run('discovery').first.song.id, 'discovery');
    });
  });
}
