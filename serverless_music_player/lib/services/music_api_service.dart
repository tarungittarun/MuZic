import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' show DESedeEngine, KeyParameter;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../app_info.dart';
import '../models/lyrics_model.dart';
import '../models/song_model.dart';
import 'recommendation_engine.dart';
import 'app_log.dart';
import 'lyrics_language.dart';

class _CachedStream {
  const _CachedStream(this.url, this.at, this.ephemeral);

  final String url;
  final DateTime at;
  final bool ephemeral;

  bool get isFresh {
    final age = DateTime.now().difference(at);
    return ephemeral
        ? age < const Duration(hours: 4)
        : age < const Duration(hours: 12);
  }
}

class MusicApiService {
  MusicApiService({http.Client? httpClient, YoutubeExplode? youtube})
      : _http = httpClient ?? http.Client(),
        _youtube = youtube ?? YoutubeExplode();

  static const String _saavnHost = 'www.jiosaavn.com';
  static const String _saavnKey = '38346591';
  static const Duration _timeout = Duration(seconds: 18);
  static const Duration _lyricsTimeout = Duration(seconds: 8);

  final http.Client _http;
  final YoutubeExplode _youtube;
  final Map<String, Future<LyricsModel>> _lyricsCache = <String, Future<LyricsModel>>{};
  final Map<String, Future<LyricsBundle>> _variantsCache =
      <String, Future<LyricsBundle>>{};
  final Map<String, _CachedStream> _streamCache = <String, _CachedStream>{};
  Future<void> _lyricsRequestQueue = Future<void>.value();
  DateTime? _lastLyricsRequestAt;
  DateTime? _lyricsRetryAfter;

  Future<List<SongModel>> search(
    String query, {
    SearchSource source = SearchSource.automatic,
    int limit = 18,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const <SongModel>[];

    if (source == SearchSource.youtube) {
      return searchYouTube(cleanQuery, limit: limit);
    }
    if (source == SearchSource.jioSaavn) {
      return limit >= 30
          ? _searchSaavnExpanded(cleanQuery, limit: limit)
          : searchJioSaavn(cleanQuery, limit: limit);
    }

    var merged = const <SongModel>[];
    try {
      merged = limit >= 30
          ? await _searchSaavnExpanded(cleanQuery, limit: limit)
          : await searchJioSaavn(cleanQuery, limit: limit);
    } catch (_) {
      // Automatic mode intentionally continues to the independent source.
    }
    if (merged.length >= limit) return merged;
    if (merged.isEmpty) return searchYouTube(cleanQuery, limit: limit);

    // A catalogue search can know the artist but only return a handful of
    // unique tracks. Fill the page from YouTube rather than showing six
    // results for a mainstream artist, then collapse cross-provider copies.
    try {
      final youtubeResults = await searchYouTube(cleanQuery, limit: limit);
      merged = dedupeSearchResults(<SongModel>[...merged, ...youtubeResults]);
    } catch (_) {
      // Keep the catalogue results if the supplement is unavailable.
    }
    return merged.take(limit).toList(growable: false);
  }

  Future<List<SongModel>> searchJioSaavn(
    String query, {
    int limit = 18,
    int page = 1,
  }) async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'search.getResults',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'p': '$page',
      'n': '$limit',
      'q': query,
    });
    try {
      final response = await _http
          .get(uri, headers: _saavnHeaders)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Source A search returned HTTP ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(response.body);
      final root = _asMap(decoded);
      final rows = _findSongRows(root ?? <String, dynamic>{});
      final parsed = rows
          .take(limit)
          .map(_songFromSaavn)
          .whereType<SongModel>()
          .toList(growable: false);
      // Providers return the same recording once per album/playlist it
      // appears on (for example a film song repeated across compilations).
      // Search should show that recording once, not a wall of copies.
      final songs = dedupeSearchResults(parsed);
      logInfo('api', 'Source A search', <String, Object?>{
        'query': query,
        'results': songs.length,
        'withUrl': songs.where((song) => song.streamUrl != null).length,
        'ms': stopwatch.elapsedMilliseconds,
      });
      return songs;
    } catch (error) {
      logWarn('api', 'Source A search failed', <String, Object?>{
        'query': query,
        'error': '$error',
        'ms': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }

  Future<List<SongModel>> _searchSaavnOrEmpty(
    String query, {
    int limit = 40,
    int page = 1,
  }) async {
    try {
      return await searchJioSaavn(query, limit: limit, page: page);
    } catch (_) {
      return const <SongModel>[];
    }
  }

  /// Deep catalogue search used by the results page (limit >= 30).
  ///
  /// One provider page is often mostly the same few recordings repeated
  /// through compilations, so this keeps paging, resolves an artist-intent
  /// query such as "arijith sing songs" to the canonical artist, searches
  /// that artist directly, and mines the artist's albums until it has a
  /// full page of *unique* songs (or the catalogue genuinely runs out).
  Future<List<SongModel>> _searchSaavnExpanded(
    String query, {
    required int limit,
  }) async {
    var merged = await searchJioSaavn(query, limit: limit < 40 ? 40 : limit);

    for (var page = 2; page <= 3 && merged.length < limit; page++) {
      final pageSongs = await _searchSaavnOrEmpty(
        query,
        limit: 40,
        page: page,
      );
      if (pageSongs.isEmpty) break;
      merged = dedupeSearchResults(<SongModel>[...merged, ...pageSongs]);
    }
    if (merged.length >= limit) {
      return merged.take(limit).toList(growable: false);
    }

    final artistName = await _canonicalArtistName(query);
    if (artistName != null) {
      final variantQueries = <String>{
        artistName,
        '$artistName songs',
        '$artistName top songs',
      }..removeWhere(
          (value) =>
              RecommendationEngine.normalise(value) ==
              RecommendationEngine.normalise(query),
        );
      final variantResults = await Future.wait<List<SongModel>>(
        <Future<List<SongModel>>>[
          for (final variant in variantQueries)
            _searchSaavnOrEmpty(variant, limit: 40),
        ],
      );
      for (final songs in variantResults) {
        merged = dedupeSearchResults(<SongModel>[...merged, ...songs]);
        if (merged.length >= limit) break;
      }

      if (merged.length < limit) {
        final albums = await searchAlbums(artistName, limit: 8);
        final albumSongs = await Future.wait<List<SongModel>>(
          <Future<List<SongModel>>>[
            for (final album in albums.take(4))
              fetchAlbumSongs(
                album.id,
                albumTitle: album.title,
                albumArtist: album.artist,
                limit: 60,
              ),
          ],
        );
        for (final songs in albumSongs) {
          merged = dedupeSearchResults(<SongModel>[
            ...merged,
            ...songs.where((song) => _isArtistSong(song, artistName)),
          ]);
          if (merged.length >= limit) break;
        }
      }
      merged = _rankArtistResults(merged, artistName);
    } else {
      final stripped = query
          .replaceAll(
            RegExp(r'[\s-]+(songs|song|tracks|track)\s*$',
                caseSensitive: false),
            '',
          )
          .trim();
      if (stripped.isNotEmpty && stripped != query) {
        final extra = await _searchSaavnOrEmpty(stripped, limit: 40);
        merged = dedupeSearchResults(<SongModel>[...merged, ...extra]);
      }
    }
    return merged.take(limit).toList(growable: false);
  }

  /// Resolves queries like "arijith sing songs" to the catalogue's
  /// canonical artist ("Arijit Singh") so the deep search can use the
  /// artist's real name instead of the user's spelling.
  Future<String?> _canonicalArtistName(String query) async {
    final base = query
        .replaceAll(
          RegExp(r'[\s-]+(songs|song|tracks|track)\s*$',
              caseSensitive: false),
          '',
        )
        .trim();
    if (base.isEmpty) return null;
    final artists = await searchArtists(base, limit: 6);
    for (final artist in artists) {
      if (_artistNameMatches(base, artist.name)) return artist.name;
    }
    return null;
  }

  static bool _artistNameMatches(String query, String artistName) {
    final wanted = RecommendationEngine.normalise(query);
    final candidate = RecommendationEngine.normalise(artistName);
    if (wanted.isEmpty || candidate.isEmpty) return false;
    if (wanted == candidate ||
        wanted.contains(candidate) ||
        candidate.contains(wanted)) {
      return true;
    }
    final wantedTokens = wanted.split(' ');
    final candidateTokens = candidate.split(' ');
    if (wantedTokens.length != candidateTokens.length) return false;
    var distance = 0;
    for (var index = 0; index < wantedTokens.length; index++) {
      distance += _editDistance(wantedTokens[index], candidateTokens[index]);
      if (distance > 3) return false;
    }
    return distance <= 3;
  }

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        var best = substitution;
        if (previous[j] + 1 < best) best = previous[j] + 1;
        if (current[j - 1] + 1 < best) best = current[j - 1] + 1;
        current[j] = best;
      }
      previous = current;
    }
    return previous[b.length];
  }

  bool _isArtistSong(SongModel song, String artistName) {
    final wanted = RecommendationEngine.normalise(artistName);
    if (wanted.isEmpty) return false;
    final credited = RecommendationEngine.artistsOf(song)
        .map(RecommendationEngine.normalise)
        .toSet();
    return credited.contains(wanted) ||
        RecommendationEngine.normalise(song.artist).contains(wanted);
  }

  List<SongModel> _rankArtistResults(
    List<SongModel> songs,
    String artistName,
  ) {
    final relevant = <SongModel>[];
    final rest = <SongModel>[];
    for (final song in songs) {
      (_isArtistSong(song, artistName) ? relevant : rest).add(song);
    }
    return <SongModel>[...relevant, ...rest];
  }

  /// Trending songs from the primary catalogue, with an independent search
  /// fallback when the chart endpoint is unavailable or returns no tracks.
  Future<List<SongModel>> fetchTrending({
    int limit = 20,
    String language = 'english',
  }) async {
    if (limit <= 0) return const <SongModel>[];
    final stopwatch = Stopwatch()..start();
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'content.getTrending',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'entity_type': 'song',
      'entity_language': language,
    });
    try {
      final response =
          await _http.get(uri, headers: _saavnHeaders).timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Trending chart returned HTTP ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(response.body);
      final rows = decoded is Iterable
          ? decoded.toList(growable: false)
          : _findSongRows(_asMap(decoded) ?? <String, dynamic>{});
      final songs = rows
          .map(_songFromSaavn)
          .whereType<SongModel>()
          .take(limit)
          .toList(growable: false);
      if (songs.isNotEmpty) {
        logInfo('api', 'fetchTrending', <String, Object?>{
          'language': language,
          'results': songs.length,
          'ms': stopwatch.elapsedMilliseconds,
        });
        return songs;
      }
      logWarn('api', 'trending chart returned no tracks; trying fallback',
          <String, Object?>{'language': language});
    } catch (error) {
      logWarn('api', 'trending chart failed; trying fallback',
          <String, Object?>{
        'language': language,
        'error': '$error',
        'ms': stopwatch.elapsedMilliseconds,
      });
    }

    final fallbackQuery = 'trending $language songs India';
    final fallback = await searchYouTube(fallbackQuery, limit: limit);
    logInfo('api', 'trending fallback completed', <String, Object?>{
      'language': language,
      'results': fallback.length,
      'ms': stopwatch.elapsedMilliseconds,
    });
    return fallback;
  }

  /// Keep the catalogue as the normal recommendation source, but recover
  /// from its outage or an empty query using the independent search source.
  Future<List<SongModel>> searchSaavnWithYouTubeFallback(
    String query, {
    int limit = 18,
  }) async {
    try {
      final primary = await searchJioSaavn(query, limit: limit);
      if (primary.isNotEmpty) return primary;
      logWarn('api', 'catalogue search returned no tracks; trying fallback',
          <String, Object?>{'query': query});
    } catch (error) {
      logWarn('api', 'catalogue search unavailable; trying fallback',
          <String, Object?>{'query': query, 'error': '$error'});
    }
    return searchYouTube(query, limit: limit);
  }

  /// Artist matches for a query. Used to open an artist library with that
  /// artist's songs and albums instead of treating every search as songs.
  Future<List<ArtistSummary>> searchArtists(
    String query, {
    int limit = 8,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const <ArtistSummary>[];
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'search.getArtistResults',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'q': cleanQuery,
      'p': '1',
      'n': '$limit',
    });
    try {
      final response =
          await _http.get(uri, headers: _saavnHeaders).timeout(_timeout);
      if (response.statusCode != 200) return const <ArtistSummary>[];
      final root = _asMap(jsonDecode(response.body));
      if (root == null) return const <ArtistSummary>[];
      final rows = root['results'] ?? root['data'];
      if (rows is! Iterable) return const <ArtistSummary>[];
      final artists = <ArtistSummary>[];
      for (final value in rows) {
        final row = _asMap(value);
        if (row == null) continue;
        final id = (row['id'] ?? row['artist_id'] ?? '').toString().trim();
        final name = _cleanText(row['title'] ?? row['name'] ?? '');
        if (id.isEmpty || name.isEmpty) continue;
        artists.add(
          ArtistSummary(
            id: id,
            name: name,
            imageUrl: _imageUrl(row['image']),
            subtitle: _cleanText(
              row['subtitle'] ?? row['description'] ?? 'Artist',
            ),
          ),
        );
        if (artists.length >= limit) break;
      }
      logInfo('api', 'searchArtists', <String, Object?>{
        'query': cleanQuery,
        'results': artists.length,
      });
      return artists;
    } catch (error) {
      logWarn('api', 'searchArtists failed', <String, Object?>{
        'query': cleanQuery,
        'error': '$error',
      });
      return const <ArtistSummary>[];
    }
  }

  /// Album matches for a query (search results page shelves).
  Future<List<AlbumSummary>> searchAlbums(
    String query, {
    int limit = 10,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const <AlbumSummary>[];
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'search.getAlbumResults',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'q': cleanQuery,
      'p': '1',
      'n': '$limit',
    });
    try {
      final response =
          await _http.get(uri, headers: _saavnHeaders).timeout(_timeout);
      if (response.statusCode != 200) return const <AlbumSummary>[];
      final root = _asMap(jsonDecode(response.body));
      if (root == null) return const <AlbumSummary>[];
      final rows = root['results'] ?? root['data'];
      if (rows is! Iterable) return const <AlbumSummary>[];
      return rows
          .map(AlbumSummary.fromSaavn)
          .whereType<AlbumSummary>()
          .take(limit)
          .toList(growable: false);
    } catch (error) {
      logWarn('api', 'searchAlbums failed', <String, Object?>{
        'query': cleanQuery,
        'error': '$error',
      });
      return const <AlbumSummary>[];
    }
  }

  /// Songs that belong to an album.
  Future<List<SongModel>> fetchAlbumSongs(
    String albumId, {
    String? albumTitle,
    String? albumArtist,
    int limit = 60,
  }) async {
    if (albumId.trim().isEmpty) return const <SongModel>[];
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'content.getAlbumDetails',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'albumid': albumId,
    });
    try {
      final response =
          await _http.get(uri, headers: _saavnHeaders).timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Album details returned HTTP ${response.statusCode}.',
          uri,
        );
      }
      final decoded = jsonDecode(response.body);
      final root = _asMap(decoded);
      final rows = root == null ? const <dynamic>[] : _findSongRows(root);
      final songs = rows
          .map(_songFromSaavn)
          .whereType<SongModel>()
          .take(limit)
          .toList(growable: false);
      logInfo('api', 'fetchAlbumSongs', <String, Object?>{
        'albumId': albumId,
        'songs': songs.length,
      });
      if (songs.isNotEmpty) return songs;
    } catch (error) {
      logWarn('api', 'fetchAlbumSongs failed', <String, Object?>{
        'albumId': albumId,
        'error': '$error',
      });
    }

    // Search results sometimes have a current album listing but the details
    // endpoint returns an empty wrapper. Recover the tracks by the visible
    // album title, and only keep results whose album metadata matches it.
    final title = albumTitle?.trim() ?? '';
    if (title.isEmpty) return const <SongModel>[];
    try {
      final candidates = await searchJioSaavn(
        title,
        limit: limit < 40 ? 40 : limit,
      );
      final matching = candidates
          .where((song) => _albumNameMatches(song.album, title))
          .take(limit)
          .toList(growable: false);
      logInfo('api', 'fetchAlbumSongs title fallback', <String, Object?>{
        'album': title,
        'artist': albumArtist ?? '',
        'songs': matching.length,
      });
      return matching;
    } catch (error) {
      logWarn('api', 'fetchAlbumSongs title fallback failed', <String, Object?>{
        'album': title,
        'error': '$error',
      });
      return const <SongModel>[];
    }
  }

  Future<List<String>> suggestions(String query) async {
    if (query.trim().isEmpty) return const <String>[];
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'autocomplete.get',
      '_format': 'json',
      '_marker': '0',
      'ctx': 'web6dot0',
      'cc': 'IN',
      'query': query.trim(),
    });
    final response = await _http
        .get(uri, headers: _saavnHeaders)
        .timeout(_timeout);
    if (response.statusCode != 200) return const <String>[];
    final root = _asMap(jsonDecode(response.body));
    if (root == null) return const <String>[];
    final raw = root['songs'] ?? root['results'] ?? root['data'];
    if (raw is! Iterable) return const <String>[];
    return raw
        .map((dynamic value) {
          final map = _asMap(value);
          return _cleanText(map?['title'] ?? map?['name'] ?? '');
        })
        .where((String value) => value.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  Future<List<SongModel>> searchYouTube(
    String query, {
    int limit = 18,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final videos = await _youtube.search.search(query).timeout(_timeout);
      final rawSongs = videos
          .where((video) => !video.isLive)
          .take(limit)
          .map((video) => SongModel(
                id: 'youtube:${video.id.value}',
                sourceId: video.id.value,
                title: _cleanText(video.title),
                artist: _cleanText(video.author),
                album: '',
                artworkUrl: video.thumbnails.highResUrl,
                source: SongSource.youtube,
                durationMs: video.duration?.inMilliseconds,
                releaseDate: _formatDate(video.publishDate ?? video.uploadDate),
                sourceUrl: video.url,
              ))
          .toList(growable: false);
      final songs = dedupeSearchResults(rawSongs);
      logInfo('api', 'Source B search', <String, Object?>{
        'query': query,
        'results': songs.length,
        'ms': stopwatch.elapsedMilliseconds,
      });
      return songs;
    } catch (error) {
      logWarn('api', 'Source B search failed', <String, Object?>{
        'query': query,
        'error': '$error',
        'ms': stopwatch.elapsedMilliseconds,
      });
      // YouTube sometimes returns markup that the parser cannot read
      // ("Streamed" consent/bot page). Treat it as "no results" so the app
      // keeps working instead of surfacing a FormatException.
      return const <SongModel>[];
    }
  }

  /// Collapses provider copies of the same recording into one search
  /// result, keeping the most usable copy (playable URL, artwork and
  /// provider quality decide). Order follows the first appearance.
  static List<SongModel> dedupeSearchResults(Iterable<SongModel> input) {
    final result = <SongModel>[];
    for (final song in input) {
      var duplicateIndex = -1;
      for (var index = 0; index < result.length; index++) {
        if (_isSameRecording(result[index], song)) {
          duplicateIndex = index;
          break;
        }
      }
      if (duplicateIndex == -1) {
        result.add(song);
      } else if (_searchCopyQuality(song) >
          _searchCopyQuality(result[duplicateIndex])) {
        result[duplicateIndex] = song;
      }
    }
    return result;
  }

  static bool _isSameRecording(SongModel a, SongModel b) {
    if (a.id == b.id) return true;
    final titleA = RecommendationEngine.canonicalTitleKey(a.title);
    final titleB = RecommendationEngine.canonicalTitleKey(b.title);
    if (titleA.isEmpty || titleA != titleB) return false;

    final artistsA = RecommendationEngine.artistsOf(a)
        .map(RecommendationEngine.normalise)
        .where((artist) => artist.isNotEmpty)
        .toSet();
    final artistsB = RecommendationEngine.artistsOf(b)
        .map(RecommendationEngine.normalise)
        .where((artist) => artist.isNotEmpty)
        .toSet();
    if (artistsA.isNotEmpty &&
        artistsA.length == artistsB.length &&
        artistsA.containsAll(artistsB)) {
      return true;
    }

    final durationA = a.duration;
    final durationB = b.duration;
    final closeDuration = durationA != null &&
        durationB != null &&
        (durationA - durationB).abs() <= const Duration(seconds: 4);
    if (!closeDuration) return false;
    if (artistsA.intersection(artistsB).isNotEmpty) return true;
    // One provider often credits only the singer while another lists the
    // full composer/singer/lyricist team for the same track.
    return artistsA.length != artistsB.length &&
        (artistsB.containsAll(artistsA) || artistsA.containsAll(artistsB));
  }

  static int _searchCopyQuality(SongModel song) {
    var quality = 0;
    if ((song.streamUrl ?? '').isNotEmpty) quality += 4;
    if (song.source == SongSource.jioSaavn) quality += 2;
    if (song.artworkUrl.isNotEmpty) quality += 1;
    if (song.duration != null) quality += 1;
    if ((song.playCount ?? 0) > 0) quality += 1;
    return quality;
  }

  /// Resolves a playable audio URL for [song].
  ///
  /// Order: in-memory cache → stable direct URL (refreshing ephemeral
  /// googlevideo links first) → JioSaavn re-search by id → YouTube fallback.
  Future<String> resolveStream(SongModel song) async {
    final stopwatch = Stopwatch()..start();

    String remember(String url) {
      _streamCache[song.id] = _CachedStream(
        url,
        DateTime.now(),
        _isEphemeralUrl(url),
      );
      logInfo('api', 'resolveStream', <String, Object?>{
        'song': song.title,
        'id': song.id,
        'host': Uri.tryParse(url)?.host ?? '?',
        'ms': stopwatch.elapsedMilliseconds,
      });
      return url;
    }

    try {
      final cached = _streamCache[song.id];
      if (cached != null && cached.isFresh) {
        logDebug('api', 'resolveStream cache hit', <String, Object?>{
          'song': song.title,
          'ageMs': DateTime.now().difference(cached.at).inMilliseconds,
        });
        return cached.url;
      }

      // Imported local files are played straight from disk.
      if (song.source == SongSource.local) {
        final path = song.localPath ?? song.streamUrl;
        if (path != null && path.isNotEmpty) {
          return remember(path);
        }
        throw StateError('This local file is no longer available.');
      }

      final direct = song.streamUrl;
      if (direct != null && MusicApiService._isHttpUrl(direct)) {
        final secure = direct.replaceFirst(RegExp(r'^http://'), 'https://');
        if (!_isEphemeralUrl(secure)) {
          return remember(secure);
        }
        // Ephemeral CDN URLs (YouTube) expire within hours; refresh them but
        // fall back to the stored URL when the refresh fails.
        try {
          final fresh = song.source == SongSource.youtube
              ? await resolveYouTube(song)
              : await resolveYouTubeFallback(song);
          return remember(fresh);
        } catch (error) {
          logWarn('api', 'ephemeral URL refresh failed; reusing stored URL',
              <String, Object?>{'song': song.title, 'error': '$error'});
          return remember(secure);
        }
      }

      if (song.source == SongSource.radio || song.source == SongSource.local) {
        throw StateError('No playable URL is stored for this track.');
      }

      if (song.source == SongSource.jioSaavn) {
        try {
          final matches = await searchJioSaavn(
            '${song.title} ${song.artist}',
            limit: 10,
          );
          SongModel? candidate;
          for (final match in matches) {
            if (match.sourceId == song.sourceId) {
              candidate = match;
              break;
            }
          }
          candidate ??= _bestTitleMatch(matches, song);
          if (candidate != null &&
              candidate.streamUrl != null &&
              MusicApiService._isHttpUrl(candidate.streamUrl!)) {
            return remember(candidate.streamUrl!);
          }
          logWarn('api', 'Source A re-search produced no usable URL',
              <String, Object?>{'song': song.title, 'matches': matches.length});
        } catch (error) {
          logWarn('api', 'Source A resolve path failed', <String, Object?>{
            'song': song.title,
            'error': '$error',
          });
        }
      }

      final fallbackUrl = song.source == SongSource.youtube
          ? await resolveYouTube(song)
          : await resolveYouTubeFallback(song);
      return remember(fallbackUrl);
    } catch (error) {
      logWarn('api', 'resolveStream failed', <String, Object?>{
        'song': song.title,
        'id': song.id,
        'error': '$error',
        'ms': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }

  Future<String> resolveYouTube(SongModel song, {bool lowestBitrate = false}) =>
      _youtubeStreamUrl(song.sourceId, lowestBitrate: lowestBitrate);

  Future<String> resolveYouTubeFallback(
    SongModel song, {
    bool lowestBitrate = false,
  }) async {
    final query = '${song.title} ${song.artist} official audio';
    final videos = await _youtube.search.search(query).timeout(_timeout);
    final matches = videos.where((item) => !item.isLive).toList();
    if (matches.isEmpty) {
      throw StateError('No matching Source B audio stream was found.');
    }
    return _youtubeStreamUrl(matches.first.id.value,
        lowestBitrate: lowestBitrate);
  }

  Future<String> _youtubeStreamUrl(
    String videoId, {
    bool lowestBitrate = false,
  }) async {
    final manifest =
        await _youtube.videos.streams.getManifest(videoId).timeout(_timeout);
    if (manifest.audioOnly.isEmpty) {
      throw StateError('No audio-only stream is available for this video.');
    }
    final AudioStreamInfo chosen;
    if (lowestBitrate) {
      chosen = manifest.audioOnly.reduce((a, b) =>
          a.bitrate.bitsPerSecond <= b.bitrate.bitsPerSecond ? a : b);
    } else {
      chosen = manifest.audioOnly.withHighestBitrate();
    }
    final url = chosen.url.toString();
    logDebug('api', 'Source B stream resolved', <String, Object?>{
      'videoId': videoId,
      'lowest': lowestBitrate,
    });
    return url;
  }

  /// Fetches every known lyrics variant for [song] (LRCLIB and JioSaavn),
  /// annotated with language/script metadata.
  Future<LyricsBundle> fetchLyricsVariants(SongModel song) {
    final cached = _variantsCache[song.id];
    if (cached != null) return cached;
    final request = _fetchLyricsVariants(song).then((bundle) {
      // A transient 503/network failure must not pin an empty result for the
      // rest of the app session; the next lyrics open should retry.
      if (bundle.isEmpty) _variantsCache.remove(song.id);
      return bundle;
    });
    _variantsCache[song.id] = request;
    return request;
  }

  Future<LyricsBundle> _fetchLyricsVariants(SongModel song) async {
    final variants = <LyricsModel>[];

    // JioSaavn is independent of LRCLIB. Start it now so it does not add its
    // network time after the (sometimes slow/rate-limited) LRCLIB calls.
    final saavnFuture = _fetchSaavnLyricsVariant(song);

    LyricsModel? primary;
    try {
      primary = await fetchLyrics(song);
      if (!primary.isEmpty) {
        variants.add(annotateLyrics(primary, song, source: primary.source));
      }
    } catch (error) {
      logWarn('api', 'lyrics: primary fetch failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
    }

    // Extra LRCLIB catalogue matches are only worth their extra request when
    // we still need lyrics or a synced version. When the primary already has
    // synced lines, returning immediately keeps the lyrics screen fast.
    if (primary == null || primary.isEmpty || !primary.hasSynced) {
      try {
        final extra = await _extraLrclibCandidates(song, variants);
        variants.addAll(extra);
      } catch (error) {
        logDebug('api', 'lyrics: extra lyrics source candidates failed', <String, Object?>{
          'song': song.title,
          'error': '$error',
        });
      }
    }

    final saavn = await saavnFuture;
    if (saavn != null && !saavn.isEmpty) variants.add(saavn);
    logInfo('api', 'lyrics variants collected', <String, Object?>{
      'song': song.title,
      'variants': variants.length,
      'languages': variants.map((variant) => variant.languageLabel).join(', '),
    });
    return LyricsBundle(songId: song.id, variants: variants);
  }

  Future<LyricsModel?> _fetchSaavnLyricsVariant(SongModel song) async {
    try {
      final saavn = await fetchSaavnLyrics(song);
      if (saavn == null || saavn.isEmpty) return null;
      return annotateLyrics(saavn, song, source: 'jiosaavn');
    } catch (error) {
      logDebug('api', 'lyrics: Source A lyrics failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
      return null;
    }
  }

  /// Up to two additional LRCLIB matches (different releases/languages),
  /// excluding duplicates of [existing].
  Future<List<LyricsModel>> _extraLrclibCandidates(
    SongModel song,
    List<LyricsModel> existing,
  ) async {
    final artists = _artistCandidates(song.artist);
    final fallbackArtist = artists.length > 1 ? artists[1] : artists.first;
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': AppInfo.userAgent,
    };
    final searchUri = Uri.https('lrclib.net', '/api/search', <String, String>{
      'track_name': song.title,
      'artist_name': fallbackArtist,
      if (song.album.trim().isNotEmpty) 'album_name': song.album,
    });
    final response = await _getLyrics(searchUri, headers);
    if (response.statusCode != 200) return const <LyricsModel>[];
    final decoded = jsonDecode(response.body);
    if (decoded is! Iterable) return const <LyricsModel>[];
    final matches = decoded.whereType<Map>().map(
          (value) => Map<String, dynamic>.from(value),
        );
    final scored = <Map<String, dynamic>>[];
    for (final match in matches) {
      if (match['instrumental'] == true) continue;
      final lyrics = _lyricsFromMap(match);
      if (lyrics.isEmpty) continue;
      scored.add(match);
      if (scored.length >= 4) break;
    }
    final seenFirstLines = existing
        .map((variant) => _firstLine(variant))
        .where((line) => line.isNotEmpty)
        .toSet();
    final extras = <LyricsModel>[];
    for (final match in scored) {
      final lyrics = annotateLyrics(_lyricsFromMap(match), song,
          source: 'lrclib');
      final key = _firstLine(lyrics);
      if (key.isEmpty || seenFirstLines.contains(key)) continue;
      seenFirstLines.add(key);
      extras.add(lyrics);
      if (extras.length >= 2) break;
    }
    return extras;
  }

  String _firstLine(LyricsModel lyrics) {
    if (lyrics.hasSynced) return lyrics.syncedLines.first.text.trim();
    return lyrics.plainLyrics.split('\n').first.trim();
  }

  /// Lyrics published by JioSaavn (usually Latin transliteration for Indian
  /// tracks). Returns null when unavailable.
  Future<LyricsModel?> fetchSaavnLyrics(SongModel song) async {
    if (song.source != SongSource.jioSaavn || song.sourceId.isEmpty) {
      return null;
    }
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'lyrics.getLyrics',
      'api_version': '4',
      'ctx': 'web6dot0',
      '_format': 'json',
      'lyrics_id': song.sourceId,
    });
    final response =
        await _http.get(uri, headers: _saavnHeaders).timeout(_lyricsTimeout);
    if (response.statusCode != 200) return null;
    final map = _asMap(jsonDecode(response.body));
    if (map == null) return null;
    final raw = map['lyrics']?.toString() ?? '';
    if (raw.trim().isEmpty) return null;
    final normalized =
        raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final text = _cleanText(normalized);
    if (text.trim().isEmpty) return null;
    return LyricsModel(plainLyrics: text.trim());
  }

  /// Fetches the best lyrics variant for [song] using [preference] (or a
  /// per-song [override]) for language selection.
  Future<LyricsModel> fetchLyrics(
    SongModel song, {
    String preference = 'auto',
    String? override,
  }) async {
    final cached = _lyricsCache[song.id];
    if (cached != null && preference == 'auto' && (override ?? '').isEmpty) {
      return cached;
    }
    final request = _fetchLyrics(song).then((raw) {
      final annotated = annotateLyrics(raw, song, source: raw.source);
      return annotated;
    });
    if (preference == 'auto' && (override ?? '').isEmpty) {
      _lyricsCache[song.id] = request;
    }
    try {
      final annotated = await request;
      if (annotated.isEmpty) return annotated;
      final selected = selectLyricsVariant(
        variants: <LyricsModel>[annotated],
        song: song,
        preference: preference,
        override: override,
      );
      return selected ?? annotated;
    } catch (_) {
      if (preference == 'auto' && (override ?? '').isEmpty) {
        _lyricsCache.remove(song.id);
      }
      rethrow;
    }
  }

  Future<LyricsModel> _fetchLyrics(SongModel song) async {
    final artists = _artistCandidates(song.artist);
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': AppInfo.userAgent,
    };
    final duration = song.duration?.inSeconds;

    // LRCLIB's exact matcher needs the correct track duration whenever it is
    // available. Try the credited artist first, then a cleaned lead-artist
    // variant for catalogues that append channel or feature credits.
    for (final artist in artists.take(2)) {
      final params = <String, String>{
        'track_name': song.title,
        'artist_name': artist,
        if (song.album.trim().isNotEmpty) 'album_name': song.album,
        if (duration != null && duration > 0 && duration <= 3600)
          'duration': '$duration',
      };
      final uri = Uri.https('lrclib.net', '/api/get', params);
      final response = await _getLyrics(uri, headers);
      if (response.statusCode == 200) {
        final data = _asMap(jsonDecode(response.body));
        final lyrics = _lyricsFromMap(data);
        if (!lyrics.isEmpty) {
          logDebug('api', 'lyrics: exact LRCLIB match', <String, Object?>{
            'song': song.title,
            'synced': lyrics.hasSynced,
          });
          return lyrics.copyWith(source: 'lrclib');
        }
      } else if (response.statusCode != 404 && response.statusCode != 400) {
        throw http.ClientException(
          'Lyrics service returned HTTP ${response.statusCode}.',
          uri,
        );
      }
    }

    // The exact endpoint is intentionally strict (including duration). Fall
    // back to the catalogue search so a slightly different release, title
    // punctuation, or artist credit can still find usable lyrics.
    final fallbackArtist = artists.length > 1 ? artists[1] : artists.first;
    final searchUri = Uri.https('lrclib.net', '/api/search', <String, String>{
      'track_name': song.title,
      'artist_name': fallbackArtist,
      if (song.album.trim().isNotEmpty) 'album_name': song.album,
    });
    final searchResponse = await _getLyrics(searchUri, headers);
    if (searchResponse.statusCode == 404) return const LyricsModel();
    if (searchResponse.statusCode != 200) {
      throw http.ClientException(
        'Lyrics search returned HTTP ${searchResponse.statusCode}.',
        searchUri,
      );
    }
    final decoded = jsonDecode(searchResponse.body);
    if (decoded is! Iterable) return const LyricsModel();
    final matches = decoded.whereType<Map>().map(
      (value) => Map<String, dynamic>.from(value),
    );
    final best = _bestLyricsMatch(matches, song, artists);
    final lyrics = _lyricsFromMap(best);
    logDebug('api', 'lyrics: search fallback', <String, Object?>{
      'song': song.title,
      'found': !lyrics.isEmpty,
    });
    return lyrics.copyWith(source: 'lrclib');
  }

  Future<http.Response> _getLyrics(
    Uri uri,
    Map<String, String> headers,
  ) {
    final request = _lyricsRequestQueue.then((_) async {
      final now = DateTime.now();
      var waitUntil = _lastLyricsRequestAt?.add(const Duration(milliseconds: 250));
      final retryAfter = _lyricsRetryAfter;
      if (retryAfter != null &&
          retryAfter.isAfter(now) &&
          (waitUntil == null || retryAfter.isAfter(waitUntil))) {
        waitUntil = retryAfter;
      }
      if (waitUntil != null && waitUntil.isAfter(now)) {
        await Future<void>.delayed(waitUntil.difference(now));
      }

      _lastLyricsRequestAt = DateTime.now();
      final response = await _http.get(uri, headers: headers).timeout(_lyricsTimeout);
      if (response.statusCode == 429 || response.statusCode == 503) {
        String? retryHeader;
        for (final entry in response.headers.entries) {
          if (entry.key.toLowerCase() == 'retry-after') {
            retryHeader = entry.value;
            break;
          }
        }
        final retrySeconds = int.tryParse(retryHeader ?? '');
        _lyricsRetryAfter = DateTime.now().add(
          Duration(seconds: retrySeconds != null && retrySeconds >= 0 ? retrySeconds : 1),
        );
      }
      return response;
    });
    _lyricsRequestQueue = request.then<void>((_) {}).catchError((Object _) {});
    return request;
  }

  LyricsModel _lyricsFromMap(Map<String, dynamic>? data) {
    if (data == null || data['instrumental'] == true) {
      return const LyricsModel();
    }
    final synced = data['syncedLyrics']?.toString() ?? '';
    final plain = data['plainLyrics']?.toString() ?? '';
    return LyricsModel(
      syncedLines: _parseLrc(synced),
      plainLyrics: plain,
    );
  }

  Map<String, dynamic>? _bestLyricsMatch(
    Iterable<Map<String, dynamic>> matches,
    SongModel song,
    List<String> artistCandidates,
  ) {
    final wantedTitle = _normalizeForMatch(song.title);
    final wantedAlbum = _normalizeForMatch(song.album);
    final wantedArtists = artistCandidates.map(_normalizeForMatch).toSet();
    final wantedDuration = song.duration?.inSeconds;
    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final match in matches) {
      if (match['instrumental'] == true) continue;
      final lyrics = _lyricsFromMap(match);
      if (lyrics.isEmpty) continue;
      final title = _normalizeForMatch(
        match['trackName'] ?? match['name'] ?? '',
      );
      final artist = _normalizeForMatch(match['artistName'] ?? '');
      final album = _normalizeForMatch(match['albumName'] ?? '');
      final titleMatches = title.isNotEmpty &&
          wantedTitle.isNotEmpty &&
          (title == wantedTitle ||
              title.contains(wantedTitle) ||
              wantedTitle.contains(title));
      if (!titleMatches) continue;
      var score = 0;
      if (title == wantedTitle) {
        score += 8;
      } else {
        score += 4;
      }
      if (wantedArtists.contains(artist) && artist.isNotEmpty) score += 6;
      if (wantedAlbum.isNotEmpty && album == wantedAlbum) score += 2;
      final matchDuration = _toInt(match['duration']);
      if (wantedDuration != null && matchDuration != null) {
        final delta = (wantedDuration - matchDuration).abs();
        if (delta <= 2) {
          score += 4;
        } else if (delta <= 10) {
          score += 1;
        }
      }
      if (score > bestScore) {
        best = match;
        bestScore = score;
      }
    }
    return best;
  }

  SongModel? _bestTitleMatch(List<SongModel> candidates, SongModel song) {
    final wantedTitle = _normalizeForMatch(song.title);
    if (wantedTitle.isEmpty) return null;
    SongModel? best;
    var bestScore = 0;
    for (final candidate in candidates) {
      if (candidate.streamUrl == null) continue;
      final title = _normalizeForMatch(candidate.title);
      if (title.isEmpty) continue;
      var score = 0;
      if (title == wantedTitle) {
        score = 3;
      } else if (title.contains(wantedTitle) || wantedTitle.contains(title)) {
        score = 2;
      } else {
        continue;
      }
      final wantedArtist = _normalizeForMatch(song.artist);
      final artist = _normalizeForMatch(candidate.artist);
      if (wantedArtist.isNotEmpty && artist.contains(wantedArtist)) score += 1;
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  List<String> _artistCandidates(String artist) {
    final raw = _cleanText(artist).trim();
    final withoutTopic = raw.replaceFirst(
      RegExp(r'\s*[-–]\s*Topic$', caseSensitive: false),
      '',
    ).trim();
    final leadArtist = withoutTopic
        .split(RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+', caseSensitive: false))
        .first
        .trim();
    final primaryArtist = leadArtist.split(RegExp(r'\s*,\s*')).first.trim();
    final candidates = <String>{raw, withoutTopic, leadArtist, primaryArtist}
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return candidates.isEmpty ? const <String>['Unknown artist'] : candidates;
  }

  String _normalizeForMatch(dynamic value) => _cleanText(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;
    final date = value.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String decryptSaavnMediaUrl(String encryptedMediaUrl) {
    final normalized = encryptedMediaUrl.trim().replaceAll(RegExp(r'\s+'), '');
    final ciphertext = base64.decode(base64.normalize(normalized));
    if (ciphertext.isEmpty || ciphertext.length % 8 != 0) {
      throw const FormatException('Invalid JioSaavn media URL payload.');
    }

    final key = Uint8List.fromList(utf8.encode(_saavnKey));
    // DESede with the same key in all three positions is equivalent to DES.
    final cipher = DESedeEngine()
      ..init(false, KeyParameter(Uint8List.fromList(<int>[...key, ...key, ...key])));
    final plaintext = Uint8List(ciphertext.length);
    for (var offset = 0; offset < ciphertext.length; offset += cipher.blockSize) {
      cipher.processBlock(ciphertext, offset, plaintext, offset);
    }

    var end = plaintext.length;
    final padding = plaintext.last;
    if (padding > 0 && padding <= cipher.blockSize && padding <= end) {
      final validPadding = plaintext
          .sublist(end - padding)
          .every((byte) => byte == padding);
      if (validPadding) end -= padding;
    }
    final url = utf8.decode(plaintext.sublist(0, end), allowMalformed: false).trim();
    final secureUrl = url.replaceFirst(RegExp(r'^http://'), 'https://');
    if (!MusicApiService._isHttpUrl(secureUrl)) {
      throw const FormatException('The decrypted media URL is not an HTTP URL.');
    }
    return secureUrl;
  }

  void dispose() {
    _http.close();
    _youtube.close();
  }

  SongModel? _songFromSaavn(dynamic value) {
    final row = _asMap(value);
    if (row == null) return null;
    final moreInfo = _asMap(row['more_info'] ?? row['moreInfo']) ?? <String, dynamic>{};
    final sourceId = (row['id'] ?? row['song_id'] ?? '').toString().trim();
    final title = _cleanText(row['title'] ?? row['song'] ?? '');
    if (sourceId.isEmpty || title.isEmpty) return null;

    final encryptedUrl = (moreInfo['encrypted_media_url'] ??
            row['encrypted_media_url'] ??
            '')
        .toString();
    String? streamUrl;
    if (encryptedUrl.isNotEmpty) {
      try {
        streamUrl = decryptSaavnMediaUrl(encryptedUrl);
        final has320 = (moreInfo['320kbps'] ?? row['320kbps'])
                ?.toString()
                .toLowerCase() ==
            'true';
        if (has320) {
          streamUrl = streamUrl.replaceFirst(
            RegExp(r'_96\.mp4(?=($|\?))'),
            '_320.mp4',
          );
        }
      } on FormatException {
        streamUrl = null;
      }
    }

    final image = _imageUrl(moreInfo['image'] ?? row['image']);
    final artist = _artistText(
      row['primary_artists'] ??
          row['singers'] ??
          moreInfo['artistMap'] ??
          moreInfo['artists'] ??
          moreInfo['music'],
    );
    final album = _cleanText(row['album'] ?? moreInfo['album'] ?? '');
    final durationSeconds = _toInt(moreInfo['duration'] ?? row['duration']);
    final artistMap = _asMap(moreInfo['artists'] ?? moreInfo['artistMap']);
    final featuredArtists = _artistNames(
      artistMap?['featured'] ??
          moreInfo['featured_artists'] ??
          row['featured_artists'],
    );
    final releaseDate = _cleanText(
      row['release_date'] ??
          moreInfo['release_date'] ??
          row['year'] ??
          moreInfo['year'],
    );
    return SongModel(
      id: 'saavn:$sourceId',
      sourceId: sourceId,
      title: title,
      artist: artist.isEmpty ? 'Unknown artist' : artist,
      album: album,
      artworkUrl: image,
      source: SongSource.jioSaavn,
      streamUrl: streamUrl,
      durationMs: durationSeconds == null || durationSeconds <= 0
          ? null
          : durationSeconds * 1000,
      releaseDate: releaseDate.isEmpty ? null : releaseDate,
      language: _cleanText(row['language'] ?? moreInfo['language']),
      label: _cleanText(row['label'] ?? moreInfo['label']),
      copyright: _cleanText(
        row['copyright_text'] ??
            row['copyright'] ??
            moreInfo['copyright_text'] ??
            moreInfo['copyright'],
      ),
      composer: _artistText(moreInfo['music'] ?? row['music']),
      featuredArtists: featuredArtists,
      playCount: _toInt(row['play_count'] ?? moreInfo['play_count']),
      hasLyrics: _toBool(
        row['has_lyrics'] ?? row['hasLyrics'] ?? moreInfo['has_lyrics'],
      ),
      isExplicit: _toBool(
        row['explicit_content'] ?? row['isExplicit'] ?? moreInfo['explicit_content'],
      ),
      sourceUrl: _cleanText(row['perma_url'] ?? row['url'] ?? moreInfo['perma_url']),
    );
  }

  List<dynamic> _findSongRows(Map<String, dynamic> root) =>
      _findSongRowsIn(root, depth: 0);

  List<dynamic> _findSongRowsIn(dynamic value, {required int depth}) {
    if (depth > 6) return const <dynamic>[];
    if (value is String && value.trim().isNotEmpty) {
      try {
        return _findSongRowsIn(jsonDecode(value), depth: depth + 1);
      } on FormatException {
        return const <dynamic>[];
      }
    }
    if (value is Iterable && value is! Map) {
      return value.toList(growable: false);
    }
    final map = _asMap(value);
    if (map == null) return const <dynamic>[];
    for (final key in const <String>[
      'results',
      'songs',
      'data',
      'tracks',
      'items',
      'list',
      'album',
      'result',
      'response',
    ]) {
      if (!map.containsKey(key)) continue;
      final rows = _findSongRowsIn(map[key], depth: depth + 1);
      if (rows.isNotEmpty) return rows;
    }
    return const <dynamic>[];
  }

  bool _albumNameMatches(String candidate, String requested) {
    final candidateText = candidate.trim().toLowerCase();
    final requestedText = requested.trim().toLowerCase();
    if (candidateText.isEmpty || requestedText.isEmpty) return false;
    if (candidateText == requestedText) return true;
    final normalizedCandidate = _normalizeForMatch(candidateText);
    final normalizedRequested = _normalizeForMatch(requestedText);
    return normalizedCandidate.isNotEmpty &&
        normalizedCandidate == normalizedRequested;
  }

  List<LyricLine> _parseLrc(String lrc) {
    final lines = <LyricLine>[];
    final timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');
    for (final rawLine in lrc.split(RegExp(r'\r?\n'))) {
      final match = timeTag.firstMatch(rawLine.trim());
      if (match == null) continue;
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fractionRaw = match.group(3) ?? '0';
      final fractionMs = int.parse(fractionRaw.padRight(3, '0').substring(0, 3));
      final text = (match.group(4) ?? '').trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine(
        time: Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: fractionMs,
        ),
        text: text,
      ));
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  Map<String, String> get _saavnHeaders => const <String, String>{
        'Accept': 'application/json, text/plain, */*',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36',
        'Referer': 'https://www.jiosaavn.com/',
      };

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  String _artistText(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final artists = map['primary'] ??
          map['primary_artists'] ??
          map['artists'] ??
          map['names'];
      if (artists != null) return _artistText(artists);
      value = map['name'] ?? map['artist'] ?? map['title'] ?? map['music'];
    }
    if (value is Iterable) {
      final names = value
          .map((dynamic item) {
            if (item is Map) {
              return _cleanText(item['name'] ?? item['artist'] ?? item['title']);
            }
            return _cleanText(item);
          })
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      return names.join(', ');
    }
    return _cleanText(value);
  }

  List<String> _artistNames(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      value = map['name'] ??
          map['artist'] ??
          map['featured'] ??
          map['featured_artists'] ??
          map['artists'];
    }
    if (value is Iterable) {
      return value
          .map((dynamic item) => item is Map
              ? _cleanText(item['name'] ?? item['artist'] ?? item['title'])
              : _cleanText(item))
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    }
    final text = _cleanText(value);
    return text.isEmpty ? const <String>[] : <String>[text];
  }

  bool? _toBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return null;
  }

  String _imageUrl(dynamic value) {
    if (value is Iterable && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) {
        value = first['url'] ?? first['link'];
      }
    } else if (value is Map) {
      value = value['url'] ?? value['link'];
    }
    final image = _cleanText(value);
    if (image.isEmpty) return '';
    return image
        .replaceFirst(RegExp(r'^http://'), 'https://')
        .replaceAll('150x150', '500x500')
        .replaceAll('50x50', '500x500');
  }

  String _cleanText(dynamic value) {
    if (value == null) return '';
    var text = value is Map
        ? (value['name'] ?? value['title'] ?? '').toString()
        : value is Iterable
            ? value.map((dynamic item) => item.toString()).join(', ')
            : value.toString();
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    text = text.replaceAllMapped(
      RegExp(r'&#(x[0-9a-fA-F]+|\d+);'),
      (match) {
        final token = match.group(1)!;
        final codePoint = token.startsWith('x')
            ? int.tryParse(token.substring(1), radix: 16)
            : int.tryParse(token);
        return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
      },
    );
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  static bool _isEphemeralUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains('googlevideo.com');
  }
}

/// Lightweight album result used by the search and discover shelves.
class ArtistSummary {
  const ArtistSummary({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.subtitle = '',
  });

  final String id;
  final String name;
  final String imageUrl;
  final String subtitle;
}

class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.title,
    required this.artist,
    this.imageUrl,
    this.year,
    this.songCount,
    this.language,
  });

  final String id;
  final String title;
  final String artist;
  final String? imageUrl;
  final String? year;
  final int? songCount;
  final String? language;

  static AlbumSummary? fromSaavn(dynamic value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final id = (map['id'] ?? map['album_id'] ?? '').toString().trim();
    final title = (map['title'] ?? map['name'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) return null;
    final moreInfo = map['more_info'] is Map
        ? Map<String, dynamic>.from(map['more_info'] as Map)
        : const <String, dynamic>{};
    final count = int.tryParse(
      (moreInfo['song_count'] ?? map['song_count'] ?? '').toString(),
    );
    return AlbumSummary(
      id: id,
      title: title,
      artist: (map['subtitle'] ?? map['artist'] ?? '').toString().trim(),
      imageUrl: (map['image'] ?? '').toString().isEmpty
          ? null
          : map['image'].toString(),
      year: (map['year'] ?? '').toString().isEmpty
          ? null
          : map['year'].toString(),
      songCount: count,
      language: (map['language'] ?? '').toString().isEmpty
          ? null
          : map['language'].toString(),
    );
  }
}
