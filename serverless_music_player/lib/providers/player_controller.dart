import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import '../services/music_api_service.dart';
import '../services/usage_service.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required AudioPlayerService audio,
    required MusicApiService musicApi,
    required DownloadService downloads,
    required LibraryService library,
    required UsageService usage,
  })  : _audio = audio,
        _musicApi = musicApi,
        _downloads = downloads,
        _library = library,
        _usage = usage {
    _subscriptions.add(_audio.player.playerStateStream.listen((_) {
      if (_audio.player.playing && _currentSong != null) {
        _recordPlaybackStart(_currentSong!);
      } else {
        _flushListeningTime();
      }
      notifyListeners();
    }));
    _subscriptions.add(_audio.player.positionStream.listen((value) {
      final delta = value - _position;
      if (_audio.player.playing &&
          _currentSong != null &&
          delta > Duration.zero &&
          delta <= const Duration(seconds: 2)) {
        _pendingListeningMs += delta.inMilliseconds;
        if (_pendingListeningMs >= 10000) _flushListeningTime();
      }
      _position = value;
      notifyListeners();
    }));
    _subscriptions.add(_audio.player.durationStream.listen((value) {
      _duration = value ?? Duration.zero;
      notifyListeners();
    }));
    _subscriptions.add(_audio.player.currentIndexStream.listen((value) {
      if (value == null || value < 0 || value >= _queue.length) return;
      _currentIndex = value;
      _currentSong = _queue[value];
      unawaited(_library.addRecent(_currentSong!));
      _recordPlaybackStart(_currentSong!);
      notifyListeners();
    }));
    _subscriptions.add(_audio.player.loopModeStream.listen((value) {
      _loopMode = value;
      notifyListeners();
    }));
    _subscriptions.add(_audio.player.shuffleModeEnabledStream.listen((value) {
      _shuffleEnabled = value;
      notifyListeners();
    }));
    _subscriptions.add(_audio.player.errorStream.listen(_onPlayerError));
  }

  final AudioPlayerService _audio;
  final MusicApiService _musicApi;
  final DownloadService _downloads;
  final LibraryService _library;
  final UsageService _usage;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  List<SongModel> _queue = <SongModel>[];
  List<AudioSource> _sources = <AudioSource>[];
  SongModel? _currentSong;
  int? _currentIndex;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  bool _isResolving = false;
  bool _isRecovering = false;
  bool _permissionAsked = false;
  String? _downloadingId;
  double _downloadProgress = 0;
  int _pendingListeningMs = 0;
  String? _lastUsageTrackId;
  final Set<String> _fallbackAttempted = <String>{};

  SongModel? get currentSong => _currentSong;
  List<SongModel> get queue => List<SongModel>.unmodifiable(_queue);
  int? get currentIndex => _currentIndex;
  Duration get position => _position;
  Duration get duration => _duration;
  LoopMode get repeatMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get isPlaying => _audio.player.playing;
  bool get isBuffering =>
      _audio.player.processingState == ProcessingState.loading ||
      _audio.player.processingState == ProcessingState.buffering;
  bool get isResolving => _isResolving;
  bool get isDownloading => _downloadingId != null;
  String? get downloadingSongId => _downloadingId;

  bool isFavorite(SongModel song) => _library.isFavorite(song.id);
  bool isDownloaded(SongModel song) => _library.isDownloaded(song.id);

  double? downloadProgressFor(SongModel song) =>
      _downloadingId == song.id ? _downloadProgress : null;

  Future<void> playQueue(
    List<SongModel> songs, {
    int initialIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final requestedIndex = initialIndex.clamp(0, songs.length - 1).toInt();
    _isResolving = true;
    notifyListeners();
    try {
      final tasks = <Future<_ResolvedTrack?>>[];
      for (var index = 0; index < songs.length; index++) {
        final originalIndex = index;
        final song = songs[index];
        tasks.add(_resolveTrack(song, originalIndex));
      }
      final resolved = (await Future.wait(tasks)).whereType<_ResolvedTrack>().toList();
      final startIndex = resolved.indexWhere(
        (track) => track.originalIndex == requestedIndex,
      );
      if (startIndex < 0) {
        throw StateError('Unable to resolve the selected track.');
      }

      _lastUsageTrackId = null;
      _queue = resolved.map((track) => track.song).toList();
      _sources = resolved.map((track) => track.source).toList();
      _currentIndex = startIndex;
      _currentSong = _queue[startIndex];
      _position = Duration.zero;
      _duration = _currentSong?.duration ?? Duration.zero;
      await _audio.setQueue(_sources, initialIndex: startIndex);
      if (_currentSong != null) _recordPlaybackStart(_currentSong!);
      await _requestNotificationPermission();
      _startPlayback();
      if (_currentSong != null) unawaited(_library.addRecent(_currentSong!));
    } finally {
      _isResolving = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    if (_audio.player.playing) {
      await _audio.player.pause();
    } else if (_queue.isNotEmpty) {
      _startPlayback();
    }
    notifyListeners();
  }

  Future<void> next() async {
    try {
      await _audio.player.seekToNext();
    } on PlayerException {
      // There is no next item when repeat is off and the queue is at its end.
    } on StateError {
      // The player can be between sources while a queue change is loading.
    }
  }

  Future<void> previous() async {
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    try {
      await _audio.player.seekToPrevious();
    } on PlayerException {
      await seek(Duration.zero);
    } on StateError {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) async {
    await _audio.player.seek(position);
  }

  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    await _audio.player.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _audio.player.setLoopMode(_loopMode);
    notifyListeners();
  }

  Future<void> toggleFavorite(SongModel song) async {
    final wasFavorite = _library.isFavorite(song.id);
    await _library.toggleFavorite(song);
    await _usage.recordSongEvent(
      wasFavorite ? 'favorite_removed' : 'favorite_added',
      song,
    );
  }

  Future<void> addToQueue(SongModel song) async {
    if (_queue.isEmpty) {
      await playQueue(<SongModel>[song]);
      return;
    }
    final track = await _resolveTrack(song, _queue.length);
    if (track == null) throw StateError('Could not add this track to the queue.');
    await _audio.append(track.source);
    _queue.add(track.song);
    _sources.add(track.source);
    await _usage.recordSongEvent('queue_add', song);
    notifyListeners();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;
    await _audio.move(oldIndex, newIndex);
    final song = _queue.removeAt(oldIndex);
    final source = _sources.removeAt(oldIndex);
    _queue.insert(newIndex, song);
    _sources.insert(newIndex, source);
    final currentId = _currentSong?.id;
    _currentIndex = currentId == null
        ? _currentIndex
        : _queue.indexWhere((item) => item.id == currentId);
    notifyListeners();
  }

  Future<void> clearUpNext() async {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return;
    final wasPlaying = _audio.player.playing;
    final keepSong = _queue[index];
    final keepSource = _sources[index];
    _queue = <SongModel>[keepSong];
    _sources = <AudioSource>[keepSource];
    _currentSong = keepSong;
    _currentIndex = 0;
    await _audio.setQueue(
      _sources,
      initialIndex: 0,
      initialPosition: _position,
    );
    if (wasPlaying) _startPlayback();
    notifyListeners();
  }

  Future<void> downloadSong(SongModel song) async {
    if (_library.isDownloaded(song.id)) {
      final path = await _downloads.localPathFor(song.id);
      if (path != null) return;
    }
    if (_downloadingId != null) {
      throw StateError('Another download is already in progress.');
    }
    _downloadingId = song.id;
    _downloadProgress = 0;
    notifyListeners();
    try {
      final streamUrl = await _musicApi.resolveStream(song);
      try {
        await _downloads.downloadSong(
          song,
          streamUrl,
          onProgress: (value) {
            _downloadProgress = value;
            notifyListeners();
          },
        );
      } catch (_) {
        if (song.source != SongSource.jioSaavn) rethrow;
        final fallbackUrl = await _musicApi.resolveYouTubeFallback(song);
        await _downloads.downloadSong(
          song.copyWith(streamUrl: fallbackUrl),
          fallbackUrl,
          onProgress: (value) {
            _downloadProgress = value;
            notifyListeners();
          },
        );
      }
      await _usage.recordSongEvent('download', song);
    } finally {
      _downloadingId = null;
      _downloadProgress = 0;
      notifyListeners();
    }
  }

  Future<void> removeDownload(SongModel song) async {
    await _downloads.removeDownload(song);
    await _usage.recordSongEvent('download_removed', song);
  }

  Future<_ResolvedTrack?> _resolveTrack(SongModel song, int originalIndex) async {
    try {
      final localPath = await _downloads.localPathFor(song.id);
      if (localPath != null) {
        return _ResolvedTrack(
          originalIndex,
          song,
          _audio.sourceFor(song, localPath: localPath),
        );
      }
      final streamUrl = await _musicApi.resolveStream(song);
      return _ResolvedTrack(
        originalIndex,
        song,
        _audio.sourceFor(song, remoteUrl: streamUrl),
      );
    } catch (error) {
      debugPrint('Track resolver failed for ${song.title}: $error');
      return null;
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_permissionAsked || !Platform.isAndroid) return;
    _permissionAsked = true;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Notification permission is optional; playback remains available.
    }
  }

  void _recordPlaybackStart(SongModel song) {
    if (_lastUsageTrackId == song.id) return;
    _lastUsageTrackId = song.id;
    unawaited(_usage.recordSongEvent('play', song));
  }

  void _flushListeningTime() {
    if (_pendingListeningMs <= 0) return;
    final elapsed = _pendingListeningMs;
    _pendingListeningMs = 0;
    unawaited(_usage.addListeningTime(Duration(milliseconds: elapsed)));
  }

  void _startPlayback() {
    unawaited(_audio.player.play().catchError((Object _) {}));
  }

  void _onPlayerError(Object error) {
    debugPrint('Audio playback error: $error');
    final song = _currentSong;
    final index = _currentIndex;
    if (song == null ||
        song.source != SongSource.jioSaavn ||
        _fallbackAttempted.contains(song.id) ||
        _isRecovering ||
        index == null ||
        index >= _sources.length) {
      return;
    }
    _fallbackAttempted.add(song.id);
    unawaited(_recoverCurrentWithYouTube(song, index));
  }

  Future<void> _recoverCurrentWithYouTube(SongModel song, int index) async {
    _isRecovering = true;
    notifyListeners();
    try {
      final url = await _musicApi.resolveYouTubeFallback(song);
      final wasPlaying = _audio.player.playing;
      final fallbackSong = song.copyWith(streamUrl: url);
      _queue[index] = fallbackSong;
      _currentSong = fallbackSong;
      _sources[index] = _audio.sourceFor(fallbackSong, remoteUrl: url);
      await _audio.setQueue(
        _sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _position = Duration.zero;
      if (wasPlaying) _startPlayback();
    } catch (fallbackError) {
      debugPrint('YouTube fallback failed: $fallbackError');
    } finally {
      _isRecovering = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _flushListeningTime();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _musicApi.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }
}

class _ResolvedTrack {
  const _ResolvedTrack(this.originalIndex, this.song, this.source);

  final int originalIndex;
  final SongModel song;
  final AudioSource source;
}
