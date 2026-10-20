import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/song_model.dart';
import '../services/app_log.dart';
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
      final song = _queue[value];
      if (_currentSong?.id != song.id) {
        _currentSong = song;
        unawaited(_library.addRecent(song));
        _recordPlaybackStart(song);
      } else {
        _currentSong = song;
      }
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
  int _playGeneration = 0;
  final Map<String, Set<String>> _fallbackAttempts = <String, Set<String>>{};

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

  /// Starts playback of [songs] beginning at [initialIndex].
  ///
  /// Only the selected track is resolved up front so playback starts fast;
  /// the rest of the queue is resolved in the background and appended in the
  /// original order as soon as each track is ready.
  Future<void> playQueue(
    List<SongModel> songs, {
    int initialIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final generation = ++_playGeneration;
    final requestedIndex = initialIndex.clamp(0, songs.length - 1).toInt();
    final requestedSong = songs[requestedIndex];
    _isResolving = true;
    notifyListeners();
    logInfo('player', 'playQueue requested', <String, Object?>{
      'song': requestedSong.title,
      'index': requestedIndex,
      'queueLength': songs.length,
    });
    try {
      final failures = <String>[];
      final first = await _resolveTrack(requestedSong, failures: failures);
      if (first == null) {
        logError('player', 'selected track could not be resolved',
            <String, Object?>{
              'song': requestedSong.title,
              'id': requestedSong.id,
              'reasons': failures.join(' | '),
            });
        final reason = failures.isEmpty
            ? 'No playable stream was found.'
            : failures.join(' ');
        throw StateError(
          'Could not play "${requestedSong.title}": $reason '
          'Check your connection or switch the search source.',
        );
      }
      if (generation != _playGeneration) return;

      _lastUsageTrackId = null;
      _queue = <SongModel>[first.song];
      _sources = <AudioSource>[first.source];
      _currentIndex = 0;
      _currentSong = first.song;
      _position = Duration.zero;
      _duration = first.song.duration ?? Duration.zero;
      await _audio.setQueue(_sources, initialIndex: 0);
      if (generation != _playGeneration) return;
      _recordPlaybackStart(first.song);
      await _requestNotificationPermission();
      _startPlayback();
      unawaited(_library.addRecent(first.song));
      logInfo('player', 'playback started', <String, Object?>{
        'song': first.song.title,
        'urlHost': Uri.tryParse(first.song.streamUrl ?? '')?.host ?? 'local',
      });
      unawaited(_fillRemainingQueue(songs, requestedIndex, generation));
    } finally {
      if (generation == _playGeneration) {
        _isResolving = false;
      }
      notifyListeners();
    }
  }

  /// Resolves every other track of the requested list and appends/inserts them
  /// so the queue keeps the original order around the started track.
  Future<void> _fillRemainingQueue(
    List<SongModel> songs,
    int startIndex,
    int generation,
  ) async {
    var added = 0;
    var skipped = 0;
    for (var i = 0; i < songs.length; i++) {
      if (i == startIndex) continue;
      if (generation != _playGeneration) return;
      final failures = <String>[];
      final track = await _resolveTrack(songs[i], failures: failures);
      if (generation != _playGeneration) return;
      if (track == null) {
        skipped++;
        logWarn('player', 'queue item skipped', <String, Object?>{
          'song': songs[i].title,
          'reasons': failures.join(' | '),
        });
        continue;
      }
      // Items before the started track are inserted at their original slot;
      // items after it are appended in order.
      final insertAt = i < startIndex ? i : _queue.length;
      final entry = track.song;
      final source = track.source;
      if (insertAt >= _queue.length) {
        _queue.add(entry);
        _sources.add(source);
        await _audio.append(source);
      } else {
        _queue.insert(insertAt, entry);
        _sources.insert(insertAt, source);
        await _audio.insert(insertAt, source);
      }
      added++;
      notifyListeners();
    }
    if (generation != _playGeneration) return;
    logInfo('player', 'queue fill finished', <String, Object?>{
      'added': added,
      'skipped': skipped,
    });
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
    final track = await _resolveTrack(song);
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
    if (song.isLiveStream) {
      throw StateError('Live radio streams cannot be downloaded.');
    }
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
      logInfo('player', 'download finished', <String, Object?>{
        'song': song.title,
      });
    } catch (error) {
      logError('player', 'download failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
      rethrow;
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

  Future<_ResolvedTrack?> _resolveTrack(
    SongModel song, {
    List<String>? failures,
  }) async {
    try {
      final localPath = await _downloads.localPathFor(song.id);
      if (localPath != null) {
        logDebug('player', 'resolve: local file', <String, Object?>{
          'song': song.title,
        });
        return _ResolvedTrack(
          song,
          _audio.sourceFor(song, localPath: localPath),
        );
      }
      final streamUrl = await _musicApi.resolveStream(song);
      final resolvedSong = song.copyWith(streamUrl: streamUrl);
      if (song.source == SongSource.local) {
        return _ResolvedTrack(
          resolvedSong,
          _audio.sourceFor(resolvedSong, localPath: streamUrl),
        );
      }
      return _ResolvedTrack(
        resolvedSong,
        _audio.sourceFor(resolvedSong, remoteUrl: streamUrl),
      );
    } catch (error) {
      debugPrint('Track resolver failed for ${song.title}: $error');
      failures?.add('$error');
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
    unawaited(_audio.player.play().catchError((Object error) {
      logWarn('player', 'play() failed', <String, Object?>{'error': '$error'});
    }));
  }

  void _onPlayerError(Object error) {
    logError('player', 'playback error', <String, Object?>{
      'error': '$error',
      'song': _currentSong?.title,
    });
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    if (_isRecovering) return;
    final attempts = _fallbackAttempts.putIfAbsent(song.id, () => <String>{});

    // First cheap retry: the 320 kbps guess is missing on some CDN entries,
    // so drop back to the standard 96 kbps URL before moving sources.
    final currentUrl = song.streamUrl ?? '';
    if (currentUrl.contains('_320.mp4') && !attempts.contains('quality')) {
      attempts.add('quality');
      unawaited(_replaceCurrentSource(
        song,
        index,
        currentUrl.replaceFirst('_320.mp4', '_96.mp4'),
        label: 'quality-96',
      ));
      return;
    }
    if (!attempts.contains('youtube')) {
      if (song.source == SongSource.radio || song.source == SongSource.local) {
        logError('player', 'no automatic fallback for this source', <String, Object?>{
          'song': song.title,
          'source': song.source.name,
        });
        return;
      }
      attempts.add('youtube');
      unawaited(_recoverCurrentWithYouTube(song, index));
      return;
    }
    logError('player', 'all fallbacks exhausted for track', <String, Object?>{
      'song': song.title,
    });
  }

  Future<void> _replaceCurrentSource(
    SongModel song,
    int index,
    String url, {
    required String label,
  }) async {
    _isRecovering = true;
    notifyListeners();
    try {
      final fallbackSong = song.copyWith(streamUrl: url);
      _queue[index] = fallbackSong;
      _sources[index] = _audio.sourceFor(fallbackSong, remoteUrl: url);
      if (_currentSong?.id == song.id) _currentSong = fallbackSong;
      await _audio.setQueue(
        _sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _position = Duration.zero;
      _startPlayback();
      logInfo('player', 'fallback applied', <String, Object?>{
        'song': song.title,
        'via': label,
      });
    } catch (fallbackError) {
      logError('player', 'fallback failed', <String, Object?>{
        'song': song.title,
        'via': label,
        'error': '$fallbackError',
      });
    } finally {
      _isRecovering = false;
      notifyListeners();
    }
  }

  Future<void> _recoverCurrentWithYouTube(SongModel song, int index) async {
    _isRecovering = true;
    notifyListeners();
    try {
      String url;
      if (song.source == SongSource.youtube) {
        try {
          url = await _musicApi.resolveYouTube(song, lowestBitrate: true);
        } catch (_) {
          url = await _musicApi.resolveYouTubeFallback(song);
        }
      } else {
        url = await _musicApi.resolveYouTubeFallback(song);
      }
      await _replaceCurrentSource(song, index, url, label: 'youtube-fallback');
    } catch (fallbackError) {
      logError('player', 'YouTube fallback failed', <String, Object?>{
        'song': song.title,
        'error': '$fallbackError',
      });
    } finally {
      _isRecovering = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _playGeneration++;
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
  const _ResolvedTrack(this.song, this.source);

  final SongModel song;
  final AudioSource source;
}
