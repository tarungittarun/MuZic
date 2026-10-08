import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/song_model.dart';

class LibraryService extends ChangeNotifier {
  late Box<dynamic> _favorites;
  late Box<dynamic> _downloads;
  late Box<dynamic> _recents;
  late Box<dynamic> _playlists;

  Future<void> init() async {
    await Hive.initFlutter();
    _favorites = await Hive.openBox<dynamic>('favorites');
    _downloads = await Hive.openBox<dynamic>('downloads');
    _recents = await Hive.openBox<dynamic>('recently_played');
    _playlists = await Hive.openBox<dynamic>('playlists');
  }

  bool isFavorite(String songId) => _favorites.containsKey(songId);

  bool isDownloaded(String songId) {
    final path = downloadedSong(songId)?.localPath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  SongModel? downloadedSong(String songId) {
    final value = _downloads.get(songId);
    if (value == null) return null;
    try {
      return SongModel.fromMap(value);
    } on FormatException {
      return null;
    }
  }

  List<SongModel> get favoriteSongs => _songsFrom(_favorites.values);

  List<SongModel> get downloadedSongs => _songsFrom(_downloads.values)
      .where((song) =>
          song.localPath != null && File(song.localPath!).existsSync())
      .toList(growable: false);

  List<SongModel> get recentSongs {
    final value = _recents.get('items', defaultValue: <dynamic>[]);
    return _songsFrom(value is Iterable ? value : const <dynamic>[]);
  }

  List<PlaylistModel> get playlists {
    return _playlists.values.map((dynamic value) {
      if (value is! Map) return null;
      final map = Map<String, dynamic>.from(value);
      final songsValue = map['songs'];
      return PlaylistModel(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Playlist',
        songs: _songsFrom(songsValue is Iterable ? songsValue : const []),
      );
    }).whereType<PlaylistModel>().toList(growable: false);
  }

  Future<void> toggleFavorite(SongModel song) async {
    if (_favorites.containsKey(song.id)) {
      await _favorites.delete(song.id);
    } else {
      await _favorites.put(song.id, song.toMap());
    }
    notifyListeners();
  }

  Future<void> addRecent(SongModel song) async {
    final current = recentSongs.where((item) => item.id != song.id).toList();
    current.insert(0, song);
    if (current.length > 40) current.removeRange(40, current.length);
    await _recents.put('items', current.map((item) => item.toMap()).toList());
    notifyListeners();
  }

  Future<void> saveDownload(SongModel song) async {
    await _downloads.put(song.id, song.toMap());
    notifyListeners();
  }

  Future<void> removeDownload(String songId) async {
    await _downloads.delete(songId);
    notifyListeners();
  }

  Future<String?> createPlaylist(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return null;
    final exists = playlists.any(
      (playlist) => playlist.name.toLowerCase() == cleanName.toLowerCase(),
    );
    if (exists) return null;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    await _playlists.put(id, <String, dynamic>{
      'id': id,
      'name': cleanName,
      'songs': <Map<String, dynamic>>[],
    });
    notifyListeners();
    return id;
  }

  Future<void> addToPlaylist(String playlistId, SongModel song) async {
    final raw = _playlists.get(playlistId);
    if (raw is! Map) return;
    final playlist = Map<String, dynamic>.from(raw);
    final songs = List<dynamic>.from(playlist['songs'] as Iterable? ?? const []);
    if (songs.any((dynamic item) => item is Map && item['id'] == song.id)) {
      return;
    }
    songs.add(song.toMap());
    playlist['songs'] = songs;
    await _playlists.put(playlistId, playlist);
    notifyListeners();
  }

  Future<void> removeFromPlaylist(String playlistId, String songId) async {
    final raw = _playlists.get(playlistId);
    if (raw is! Map) return;
    final playlist = Map<String, dynamic>.from(raw);
    final songs = List<dynamic>.from(playlist['songs'] as Iterable? ?? const []);
    songs.removeWhere((dynamic item) => item is Map && item['id'] == songId);
    playlist['songs'] = songs;
    await _playlists.put(playlistId, playlist);
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _playlists.delete(playlistId);
    notifyListeners();
  }

  List<SongModel> _songsFrom(Iterable<dynamic> values) {
    final result = <SongModel>[];
    for (final value in values) {
      try {
        result.add(SongModel.fromMap(value));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result;
  }
}
