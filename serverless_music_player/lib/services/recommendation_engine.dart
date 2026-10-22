import '../models/song_model.dart';

/// A song discovered from one recommendation "lane" (an artist the listener
/// plays, an album context, a language chart, a previous search, and so on).
class RecommendationCandidate {
  const RecommendationCandidate({
    required this.song,
    required this.lane,
    this.laneBoost = 0,
  });

  final SongModel song;

  /// Human/debug name for where this candidate came from.
  final String lane;

  /// Small lane-specific boost before personalisation is applied.
  final double laneBoost;
}

/// A candidate after personalised ranking, with the main reason it was chosen.
class RankedRecommendation {
  const RankedRecommendation({
    required this.song,
    required this.score,
    required this.reason,
  });

  final SongModel song;
  final double score;
  final String reason;
}

/// Pure, testable recommendation ranking.
///
/// Spotify/YouTube-style radio is not "search the exact title again". It mixes
/// a listener profile (favourites, recents, repeated plays, searches and the
/// current queue), the seed track's artists/language/album, and discovery
/// charts. This class owns the filtering and diversity rules; networking stays
/// in [PlayerController].
class RecommendationEngine {
  const RecommendationEngine._();

  static List<RankedRecommendation> rank({
    required Iterable<RecommendationCandidate> candidates,
    required SongModel seed,
    required Set<String> excludedIds,
    required Set<String> excludedTitleKeys,
    required Set<String> recentlyPlayedIds,
    required Set<String> recentTitleKeys,
    required Set<String> previouslyRecommendedIds,
    required Map<String, double> artistAffinity,
    required Set<String> preferredLanguages,
    String style = 'balanced',
    int limit = 8,
  }) {
    if (limit <= 0) return const <RankedRecommendation>[];

    final seedTitleKey = canonicalTitleKey(seed.title);
    final seedArtists = artistsOf(seed).map(normalise).toSet();
    final seedPrimaryArtist = primaryArtistKey(seed);
    final seedLanguage = normalise(seed.language);
    final preferred = preferredLanguages.map(normalise).toSet();

    // First collapse alternate uploads/versions of the same recording. Keep
    // the copy that looks most playable and authoritative.
    final byTitle = <String, RecommendationCandidate>{};
    final byId = <String, RecommendationCandidate>{};
    for (final candidate in candidates) {
      final song = candidate.song;
      if (!_isEligible(
        song,
        seedTitleKey: seedTitleKey,
        excludedIds: excludedIds,
        excludedTitleKeys: excludedTitleKeys,
        recentlyPlayedIds: recentlyPlayedIds,
        recentTitleKeys: recentTitleKeys,
        previouslyRecommendedIds: previouslyRecommendedIds,
      )) {
        continue;
      }
      final previousById = byId[song.id];
      if (previousById == null ||
          _candidateQuality(candidate) > _candidateQuality(previousById)) {
        byId[song.id] = candidate;
      }
      final titleKey = canonicalTitleKey(song.title);
      final previous = byTitle[titleKey];
      if (previous == null ||
          _candidateQuality(candidate) > _candidateQuality(previous)) {
        byTitle[titleKey] = candidate;
      }
    }

    final uniqueById = <String, RecommendationCandidate>{};
    for (final candidate in byTitle.values) {
      final previous = uniqueById[candidate.song.id];
      if (previous == null ||
          _candidateQuality(candidate) > _candidateQuality(previous)) {
        uniqueById[candidate.song.id] = candidate;
      }
    }

    final scored = <RankedRecommendation>[];
    for (final candidate in uniqueById.values) {
      final song = candidate.song;
      final songArtists = artistsOf(song);
      final normalisedArtists = songArtists.map(normalise).toSet();
      var affinity = 0.0;
      String? affinityArtist;
      for (final artist in songArtists) {
        final value = artistAffinity[normalise(artist)] ?? 0;
        if (value > affinity) {
          affinity = value;
          affinityArtist = artist;
        }
      }

      var score = 18 + candidate.laneBoost + _candidateQuality(candidate);
      var reason = 'Fresh pick for this session';

      final familiarMultiplier = switch (style) {
        'familiar' => 1.35,
        'discovery' => 0.55,
        _ => 1.0,
      };
      final affinityPoints = (affinity * 2.4).clamp(0, 30).toDouble();
      score += affinityPoints * familiarMultiplier;
      if (affinity >= 5 && affinityArtist != null) {
        reason = 'Because you listen to $affinityArtist';
      }

      final sharesSeedArtist = normalisedArtists.intersection(seedArtists);
      if (sharesSeedArtist.isNotEmpty) {
        score += 14;
        final displayArtist = songArtists.firstWhere(
          (artist) => seedArtists.contains(normalise(artist)),
          orElse: () => songArtists.isEmpty ? song.artist : songArtists.first,
        );
        reason = 'More from $displayArtist';
      }
      if (normalise(song.artist) == seedPrimaryArtist &&
          seedPrimaryArtist.isNotEmpty) {
        score += 5;
      }

      final language = normalise(song.language);
      if (language.isNotEmpty && language == seedLanguage) {
        score += 13;
        if (affinity < 5 && sharesSeedArtist.isEmpty) {
          reason = 'Same language as this track';
        }
      } else if (language.isNotEmpty && preferred.contains(language)) {
        score += 7;
        if (affinity < 5 && sharesSeedArtist.isEmpty) {
          reason = 'Popular in your selected languages';
        }
      }

      switch (candidate.lane) {
        case 'album':
          score += 6;
          if (sharesSeedArtist.isEmpty) reason = 'From the same album world';
          break;
        case 'trending':
          score += style == 'discovery' ? 12 : 7;
          if (affinity < 5 && sharesSeedArtist.isEmpty) {
            reason = language.isEmpty
                ? 'Trending now'
                : 'Trending in ${_titleCase(song.language)}';
          }
          break;
        case 'search':
          score += 5;
          if (affinity < 5 && sharesSeedArtist.isEmpty) {
            reason = 'Inspired by your searches';
          }
          break;
        case 'favourite':
        case 'artist':
          score += 4;
          break;
      }

      final playCount = song.playCount;
      if (playCount != null && playCount > 0) {
        // Log scale: popularity helps, but does not swamp personal taste.
        var digits = 0;
        var value = playCount;
        while (value >= 10) {
          value ~/= 10;
          digits++;
        }
        score += (digits * 1.35).clamp(0, 10).toDouble();
      }

      final duration = song.duration;
      if (duration != null &&
          duration >= const Duration(seconds: 120) &&
          duration <= const Duration(minutes: 6)) {
        score += 3;
      }
      if (song.artworkUrl.isNotEmpty) score += 1.5;

      scored.add(
        RankedRecommendation(song: song, score: score, reason: reason),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return canonicalTitleKey(a.song.title)
          .compareTo(canonicalTitleKey(b.song.title));
    });

    // Greedy diversity passes. A radio queue made of eight songs by one or
    // two artists feels like an artist search, not a recommendation feed.
    final selected = <RankedRecommendation>[];
    final selectedIds = <String>{};
    for (final artistCap in <int>[1, 2, 3]) {
      for (final item in scored) {
        if (selected.length >= limit) break;
        if (selectedIds.contains(item.song.id)) continue;
        final artist = primaryArtistKey(item.song);
        final sameArtist = selected
            .where((entry) => primaryArtistKey(entry.song) == artist)
            .length;
        if (artist.isNotEmpty && sameArtist >= artistCap) continue;
        final album = normalise(item.song.album);
        final sameAlbum = album.isEmpty
            ? 0
            : selected.where((entry) => normalise(entry.song.album) == album).length;
        if (album.isNotEmpty && sameAlbum >= 2) continue;
        selected.add(item);
        selectedIds.add(item.song.id);
      }
      if (selected.length >= limit) break;
    }
    return selected;
  }

  static bool _isEligible(
    SongModel song, {
    required String seedTitleKey,
    required Set<String> excludedIds,
    required Set<String> excludedTitleKeys,
    required Set<String> recentlyPlayedIds,
    required Set<String> recentTitleKeys,
    required Set<String> previouslyRecommendedIds,
  }) {
    if (song.isLiveStream || song.title.trim().isEmpty) return false;
    if (excludedIds.contains(song.id) ||
        recentlyPlayedIds.contains(song.id) ||
        previouslyRecommendedIds.contains(song.id)) {
      return false;
    }
    final titleKey = canonicalTitleKey(song.title);
    if (titleKey.isEmpty || titleKey == seedTitleKey) return false;
    if (excludedTitleKeys.contains(titleKey) ||
        recentTitleKeys.contains(titleKey)) {
      return false;
    }
    final duration = song.duration;
    if (duration != null &&
        (duration < const Duration(seconds: 40) ||
            duration > const Duration(minutes: 15))) {
      return false;
    }
    return true;
  }

  static double _candidateQuality(RecommendationCandidate candidate) {
    final song = candidate.song;
    var quality = candidate.laneBoost;
    if ((song.streamUrl ?? '').isNotEmpty) quality += 4;
    if (song.artworkUrl.isNotEmpty) quality += 1;
    if (song.source == SongSource.jioSaavn) quality += 2;
    if (song.duration != null) quality += 1;
    return quality;
  }

  /// Splits a credit blob into individual artist display names.
  static List<String> artistNames(String raw) {
    final result = <String>[];
    final seen = <String>{};
    final cleaned = raw.replaceAll(
      RegExp(r'\s*[-–]\s*Topic$', caseSensitive: false),
      '',
    );
    for (final part in cleaned.split(
      RegExp(
        r'\s*(?:,|&|;|•|\bx\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b)\s*',
        caseSensitive: false,
      ),
    )) {
      final artist = part.trim();
      final key = normalise(artist);
      if (artist.isEmpty || key == 'unknown' || key == 'unknown artist') {
        continue;
      }
      if (seen.add(key)) result.add(artist);
    }
    return result;
  }

  static List<String> artistsOf(SongModel song) {
    final result = <String>[];
    final seen = <String>{};
    void addBlob(String raw) {
      for (final artist in artistNames(raw)) {
        if (seen.add(normalise(artist))) result.add(artist);
      }
    }

    addBlob(song.artist);
    for (final artist in song.featuredArtists) {
      addBlob(artist);
    }
    if (song.composer.trim().isNotEmpty) addBlob(song.composer);
    return result;
  }

  static String primaryArtistKey(SongModel song) {
    final artists = artistsOf(song);
    return artists.isEmpty ? normalise(song.artist) : normalise(artists.first);
  }

  /// Recording-level identity: alternate versions/uploads of the same title
  /// collapse even when they come from different providers.
  static String canonicalTitleKey(String title) {
    var value = title.toLowerCase().replaceAll('&', ' and ');
    value = value.replaceAllMapped(
      RegExp(r'\(([^)]*)\)|\[([^\]]*)\]'),
      (match) {
        final inside = (match.group(1) ?? match.group(2) ?? '').toLowerCase();
        const removable = <String>[
          'feat',
          'ft',
          'featuring',
          'remix',
          'live',
          'version',
          'official',
          'lyric',
          'lyrics',
          'video',
          'audio',
          'remaster',
          'acoustic',
          'unplugged',
          'reprise',
          'edit',
          'mix',
        ];
        return removable.any(inside.contains) ? ' ' : ' ${match.group(0)} ';
      },
    );
    final featAt = value.indexOf(RegExp(r'\b(feat|ft|featuring)\b'));
    if (featAt >= 0) value = value.substring(0, featAt);
    final parts = value.split(' - ');
    if (parts.length > 1) {
      final suffix = parts.sublist(1).join(' ');
      const suffixWords = <String>[
        'remaster',
        'remix',
        'live',
        'version',
        'official',
        'lyric',
        'video',
        'audio',
        'acoustic',
        'unplugged',
        'reprise',
        'edit',
      ];
      if (suffixWords.any(suffix.contains)) value = parts.first;
    }
    value = value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final words = value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    const trailing = <String>{
      'remastered',
      'remix',
      'live',
      'acoustic',
      'unplugged',
      'reprise',
      'version',
      'edit',
      'mix',
    };
    while (words.isNotEmpty && trailing.contains(words.last)) {
      words.removeLast();
    }
    return words.join(' ');
  }

  static String songKey(SongModel song) =>
      '${canonicalTitleKey(song.title)}|${primaryArtistKey(song)}';

  static String normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _titleCase(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return clean;
    return clean[0].toUpperCase() + clean.substring(1);
  }
}
