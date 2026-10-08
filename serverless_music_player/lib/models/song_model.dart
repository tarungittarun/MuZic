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
      localPath: map['localPath']?.toString(),
      localArtworkPath: map['localArtworkPath']?.toString(),
    );
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
