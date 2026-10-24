import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A lyric video that was rendered on this device.
///
/// Lyric videos are stored separately from audio downloads, can be played in
/// the app, and can also be shared from the device. Keeping a record lets the
/// Downloads tab list them alongside—but distinct from—audio.
class VideoExportRecord {
  const VideoExportRecord({
    required this.id,
    required this.songId,
    required this.title,
    required this.artist,
    required this.path,
    required this.createdAtMs,
    this.artworkPath,
    this.durationMs,
  });

  final String id;
  final String songId;
  final String title;
  final String artist;
  final String path;
  final int createdAtMs;
  final String? artworkPath;
  final int? durationMs;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'songId': songId,
        'title': title,
        'artist': artist,
        'path': path,
        'createdAtMs': createdAtMs,
        'artworkPath': artworkPath,
        'durationMs': durationMs,
      };

  static VideoExportRecord? fromJson(Map<String, dynamic> map) {
    final path = map['path']?.toString();
    if (path == null || path.isEmpty) return null;
    return VideoExportRecord(
      id: map['id']?.toString() ?? path,
      songId: map['songId']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Lyric video',
      artist: map['artist']?.toString() ?? '',
      path: path,
      createdAtMs:
          int.tryParse(map['createdAtMs']?.toString() ?? '') ?? 0,
      artworkPath: map['artworkPath']?.toString(),
      durationMs: int.tryParse(map['durationMs']?.toString() ?? ''),
    );
  }
}

/// Persists the list of rendered lyric videos.
class VideoLibraryService extends ChangeNotifier {
  VideoLibraryService({File? store}) : _storeOverride = store;

  final File? _storeOverride;
  File? _store;
  List<VideoExportRecord> _videos = <VideoExportRecord>[];

  List<VideoExportRecord> get videos => List<VideoExportRecord>.unmodifiable(_videos);

  int get count => _videos.length;

  bool get isEmpty => _videos.isEmpty;

  Future<void> init() async {
    _store = _storeOverride ?? await _defaultStore();
    try {
      if (!await _store!.exists()) return;
      final raw = await _store!.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final items = <VideoExportRecord>[];
      for (final entry in decoded) {
        if (entry is Map) {
          final record = VideoExportRecord.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (record != null) items.add(record);
        }
      }
      items.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      _videos = items;
      notifyListeners();
    } catch (_) {
      // A corrupt list must never stop the app from starting.
      _videos = <VideoExportRecord>[];
    }
  }

  Future<VideoExportRecord> add({
    required String songId,
    required String title,
    required String artist,
    required String path,
    String? artworkPath,
    int? durationMs,
  }) async {
    final record = VideoExportRecord(
      id: 'video:${DateTime.now().microsecondsSinceEpoch}',
      songId: songId,
      title: title,
      artist: artist,
      path: path,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      artworkPath: artworkPath,
      durationMs: durationMs,
    );
    _videos = <VideoExportRecord>[record, ..._videos];
    await _persist();
    notifyListeners();
    return record;
  }

  /// Removes the record. The video itself stays in its saved folder; deleting
  /// a user's video from shared storage is not this list's job.
  Future<void> remove(String id) async {
    _videos = _videos.where((video) => video.id != id).toList();
    await _persist();
    notifyListeners();
  }

  bool hasVideoFor(String songId) =>
      songId.isNotEmpty && _videos.any((video) => video.songId == songId);

  /// Drops records whose file disappeared from the device.
  Future<void> pruneMissing() async {
    if (_videos.isEmpty) return;
    final alive = <VideoExportRecord>[];
    for (final video in _videos) {
      if (video.path.startsWith('content://')) {
        // MediaStore URIs cannot be stat-checked cheaply; keep them.
        alive.add(video);
      } else if (await File(video.path).exists()) {
        alive.add(video);
      }
    }
    if (alive.length != _videos.length) {
      _videos = alive;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.parent.create(recursive: true);
      await store.writeAsString(
        jsonEncode(<Map<String, dynamic>>[
          for (final video in _videos) video.toJson(),
        ]),
        flush: true,
      );
    } on FileSystemException {
      // Nothing useful to do: the in-memory list still drives the UI.
    }
  }

  Future<File> _defaultStore() async {
    final root = await getApplicationDocumentsDirectory();
    return File(p.join(root.path, 'lyric_videos.json'));
  }
}
