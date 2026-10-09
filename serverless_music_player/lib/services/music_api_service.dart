import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' show DESedeEngine, KeyParameter;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/lyrics_model.dart';
import '../models/song_model.dart';

class MusicApiService {
  MusicApiService({http.Client? httpClient, YoutubeExplode? youtube})
      : _http = httpClient ?? http.Client(),
        _youtube = youtube ?? YoutubeExplode();

  static const String _saavnHost = 'www.jiosaavn.com';
  static const String _saavnKey = '38346591';
  static const Duration _timeout = Duration(seconds: 18);

  final http.Client _http;
  final YoutubeExplode _youtube;
  final Map<String, Future<LyricsModel>> _lyricsCache = <String, Future<LyricsModel>>{};
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
      return searchJioSaavn(cleanQuery, limit: limit);
    }

    try {
      final saavnResults = await searchJioSaavn(cleanQuery, limit: limit);
      if (saavnResults.isNotEmpty) return saavnResults;
    } catch (_) {
      // Automatic mode intentionally continues to the independent source.
    }
    return searchYouTube(cleanQuery, limit: limit);
  }

  Future<List<SongModel>> searchJioSaavn(
    String query, {
    int limit = 18,
  }) async {
    final uri = Uri.https(_saavnHost, '/api.php', <String, String>{
      '__call': 'search.getResults',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'p': '1',
      'n': '$limit',
      'q': query,
    });
    final response = await _http
        .get(uri, headers: _saavnHeaders)
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'JioSaavn search returned HTTP ${response.statusCode}.',
        uri,
      );
    }
    final decoded = jsonDecode(response.body);
    final root = _asMap(decoded);
    if (root == null) return const <SongModel>[];
    final rows = _findSongRows(root);
    return rows
        .take(limit)
        .map(_songFromSaavn)
        .whereType<SongModel>()
        .toList(growable: false);
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
    final videos = await _youtube.search.search(query).timeout(_timeout);
    return videos
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
  }

  Future<String> resolveStream(SongModel song) async {
    final direct = song.streamUrl;
    if (direct != null && MusicApiService._isHttpUrl(direct)) {
      return direct.replaceFirst(RegExp(r'^http://'), 'https://');
    }
    if (song.source == SongSource.youtube) return resolveYouTube(song);

    try {
      final matches = await searchJioSaavn(
        '${song.title} ${song.artist}',
        limit: 10,
      );
      final exact = matches.where((item) => item.sourceId == song.sourceId);
      final candidate = exact.isNotEmpty
          ? exact.first
          : (matches.isEmpty ? null : matches.first);
      if (candidate?.streamUrl != null &&
          MusicApiService._isHttpUrl(candidate!.streamUrl!)) {
        return candidate.streamUrl!;
      }
    } catch (_) {
      // If the public catalog is unavailable, try the second source below.
    }
    return resolveYouTubeFallback(song);
  }

  Future<String> resolveYouTube(SongModel song) async {
    final manifest = await _youtube.videos.streams
        .getManifest(song.sourceId)
        .timeout(_timeout);
    if (manifest.audioOnly.isEmpty) {
      throw StateError('No audio-only stream is available for this video.');
    }
    return manifest.audioOnly.withHighestBitrate().url.toString();
  }

  Future<String> resolveYouTubeFallback(SongModel song) async {
    final query = '${song.title} ${song.artist} official audio';
    final videos = await _youtube.search.search(query).timeout(_timeout);
    final matches = videos.where((item) => !item.isLive).toList();
    if (matches.isEmpty) {
      throw StateError('No matching YouTube audio stream was found.');
    }
    final video = matches.first;
    final manifest = await _youtube.videos.streams
        .getManifest(video.id.value)
        .timeout(_timeout);
    if (manifest.audioOnly.isEmpty) {
      throw StateError('The matching video has no audio-only stream.');
    }
    return manifest.audioOnly.withHighestBitrate().url.toString();
  }

  Future<LyricsModel> fetchLyrics(SongModel song) async {
    final cached = _lyricsCache[song.id];
    if (cached != null) return cached;
    final request = _fetchLyrics(song);
    _lyricsCache[song.id] = request;
    try {
      return await request;
    } catch (_) {
      _lyricsCache.remove(song.id);
      rethrow;
    }
  }

  Future<LyricsModel> _fetchLyrics(SongModel song) async {
    final artists = _artistCandidates(song.artist);
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'Auralis/1.0.0 (https://github.com/tarungittarun/MuZic)',
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
        if (!lyrics.isEmpty) return lyrics;
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
    return _lyricsFromMap(best);
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
      final response = await _http.get(uri, headers: headers).timeout(_timeout);
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

  List<dynamic> _findSongRows(Map<String, dynamic> root) {
    dynamic candidate = root['results'] ?? root['songs'] ?? root['data'];
    if (candidate is Map) {
      final map = _asMap(candidate);
      if (map == null) return const <dynamic>[];
      candidate = map['results'] ?? map['songs'] ?? map['data'];
    }
    if (candidate is Iterable) return candidate.toList(growable: false);
    return const <dynamic>[];
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
}
