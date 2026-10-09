enum SongSource { jioSaavn, youtube }

enum SearchSource { automatic, jioSaavn, youtube }

class SongModel {
  const SongModel({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.artist,
    required this.source,
    this.album = '',
    this.artworkUrl = '',
    this.streamUrl,
    this.durationMs,
    this.releaseDate,
    this.language = '',
    this.label = '',
    this.copyright = '',
    this.composer = '',
    this.featuredArtists = const <String>[],
    this.playCount,
    this.hasLyrics,
    this.isExplicit,
    this.sourceUrl,
    this.localPath,
    this.localArtworkPath,
  });

  final String id;
  final String sourceId;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final SongSource source;
  final String? streamUrl;
  final int? durationMs;
  final String? releaseDate;
  final String language;
  final String label;
  final String copyright;
  final String composer;
  final List<String> featuredArtists;
  final int? playCount;
  final bool? hasLyrics;
  final bool? isExplicit;
  final String? sourceUrl;
  final String? localPath;
  final String? localArtworkPath;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  SongModel copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    SongSource? source,
    String? streamUrl,
    int? durationMs,
    String? releaseDate,
    String? language,
    String? label,
    String? copyright,
    String? composer,
    List<String>? featuredArtists,
    int? playCount,
    bool? hasLyrics,
    bool? isExplicit,
    String? sourceUrl,
    String? localPath,
    String? localArtworkPath,
    bool clearLocalFiles = false,
  }) {
    return SongModel(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      source: source ?? this.source,
      streamUrl: streamUrl ?? this.streamUrl,
      durationMs: durationMs ?? this.durationMs,
      releaseDate: releaseDate ?? this.releaseDate,
      language: language ?? this.language,
      label: label ?? this.label,
      copyright: copyright ?? this.copyright,
      composer: composer ?? this.composer,
      featuredArtists: featuredArtists ?? this.featuredArtists,
      playCount: playCount ?? this.playCount,
      hasLyrics: hasLyrics ?? this.hasLyrics,
      isExplicit: isExplicit ?? this.isExplicit,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      localPath: clearLocalFiles ? null : (localPath ?? this.localPath),
      localArtworkPath:
          clearLocalFiles ? null : (localArtworkPath ?? this.localArtworkPath),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'sourceId': sourceId,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'source': source.name,
        'streamUrl': streamUrl,
        'durationMs': durationMs,
        'releaseDate': releaseDate,
        'language': language,
        'label': label,
        'copyright': copyright,
        'composer': composer,
        'featuredArtists': featuredArtists,
        'playCount': playCount,
        'hasLyrics': hasLyrics,
        'isExplicit': isExplicit,
        'sourceUrl': sourceUrl,
        'localPath': localPath,
        'localArtworkPath': localArtworkPath,
      };

  factory SongModel.fromMap(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Song data must be a map.');
    }
    final map = Map<String, dynamic>.from(value);
    final sourceName = map['source']?.toString();
    final source = SongSource.values.firstWhere(
      (candidate) => candidate.name == sourceName,
      orElse: () => SongSource.jioSaavn,
    );
    final rawFeaturedArtists = map['featuredArtists'];
    return SongModel(
      id: map['id']?.toString() ?? '',
      sourceId: map['sourceId']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Unknown track',
      artist: map['artist']?.toString() ?? 'Unknown artist',
      album: map['album']?.toString() ?? '',
      artworkUrl: map['artworkUrl']?.toString() ?? '',
      source: source,
      streamUrl: map['streamUrl']?.toString(),
      durationMs: map['durationMs'] is num
          ? (map['durationMs'] as num).toInt()
          : int.tryParse(map['durationMs']?.toString() ?? ''),
      releaseDate: map['releaseDate']?.toString(),
      language: map['language']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      copyright: map['copyright']?.toString() ?? '',
      composer: map['composer']?.toString() ?? '',
      featuredArtists: rawFeaturedArtists is Iterable
          ? rawFeaturedArtists.map((dynamic item) => item.toString()).toList()
          : const <String>[],
      playCount: _toInt(map['playCount']),
      hasLyrics: _toBool(map['hasLyrics']),
      isExplicit: _toBool(map['isExplicit']),
      sourceUrl: map['sourceUrl']?.toString(),
      localPath: map['localPath']?.toString(),
      localArtworkPath: map['localArtworkPath']?.toString(),
    );
  }

  static int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool? _toBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return null;
  }
}

class PlaylistModel {
  const PlaylistModel({
    required this.id,
    required this.name,
    required this.songs,
  });

  final String id;
  final String name;
  final List<SongModel> songs;
}
