import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/song_model.dart';
import '../services/app_log.dart';
import '../services/app_settings_service.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import '../services/music_api_service.dart';
import '../services/playback_recovery.dart';
import '../services/recommendation_engine.dart';
import '../services/usage_service.dart';

class PlayerController extends ChangeNotifier {
  static const Duration _bufferingTimeout = Duration(seconds: 15);

  PlayerController({
    required AudioPlayerService audio,
    required MusicApiService musicApi,
    required DownloadService downloads,
    required LibraryService library,
    required UsageService usage,
    AppSettingsService? settings,
  })  : _audio = audio,
        _musicApi = musicApi,
        _downloads = downloads,
        _library = library,
        _usage = usage,
        _settings = settings {
    _subscriptions.add(_audio.player.playerStateStream.listen((_) {
      if (_audio.player.playing && _currentSong != null) {
        _recordPlaybackStart(_currentSong!);
      } else {
        _flushListeningTime();
      }
      _refreshBufferingWatchdog();
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
        _playbackError = null;
        final automaticRecommendation =
            _recommendationReasons.containsKey(song.id);
        if (!automaticRecommendation) unawaited(_library.addRecent(song));
        _recordPlaybackStart(
          song,
          isRecommendation: automaticRecommendation,
        );
      } else {
        _currentSong = song;
      }
      _refreshBufferingWatchdog();
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
  final AppSettingsService? _settings;
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
  bool _downloadCancelRequested = false;
  Completer<void>? _downloadCancelSignal;
  final List<SongModel> _recommendations = <SongModel>[];
  final Map<String, String> _recommendationReasons = <String, String>{};
  int _pendingListeningMs = 0;
  String? _lastUsageTrackId;
  int _playGeneration = 0;
  Timer? _bufferingWatchdog;
  String? _watchdogSongId;
  int _watchdogGeneration = -1;
  String? _playbackError;
  final Map<String, Set<String>> _fallbackAttempts = <String, Set<String>>{};

  SongModel? get currentSong => _currentSong;
  List<SongModel> get queue => List<SongModel>.unmodifiable(_queue);

  /// Related songs MuZic lined up automatically after the user's queue.
  /// They are real queue items and appear at the end of Up next.
  List<SongModel> get recommendations =>
      List<SongModel>.unmodifiable(_recommendations);

  Set<String> get recommendationIds =>
      _recommendations.map((song) => song.id).toSet();

  /// Why a recommended song was selected, for its Up next row.
  String recommendationReasonFor(SongModel song) =>
      _recommendationReasons[song.id] ?? '';
  int? get currentIndex => _currentIndex;
  Duration get position => _position;
  Duration get duration => _duration;
  LoopMode get repeatMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get isPlaying => _audio.player.playing;
  bool get isBuffering =>
      _playbackError == null &&
      (_audio.player.processingState == ProcessingState.loading ||
          _audio.player.processingState == ProcessingState.buffering);
  bool get isResolving => _isResolving || _isRecovering;
  String? get playbackError => _playbackError;
  bool get isDownloading => _downloadingId != null;
  String? get downloadingSongId => _downloadingId;

  bool isFavorite(SongModel song) => _library.isFavorite(song.id);
  bool isDownloaded(SongModel song) => _library.isDownloaded(song.id);

  double? downloadProgressFor(SongModel song) =>
      _downloadingId == song.id ? _downloadProgress : null;

  void _cancelBufferingWatchdog() {
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    _watchdogSongId = null;
    _watchdogGeneration = -1;
  }

  void _refreshBufferingWatchdog() {
    final song = _currentSong;
    final processingState = _audio.player.processingState;
    final stalledState = processingState == ProcessingState.loading ||
        processingState == ProcessingState.buffering;
    final shouldWatch = song != null &&
        _playbackError == null &&
        !_isResolving &&
        !_isRecovering &&
        _audio.player.playing &&
        stalledState;

    if (!shouldWatch || song == null) {
      _cancelBufferingWatchdog();
      return;
    }
    if (_bufferingWatchdog != null &&
        _watchdogSongId == song.id &&
        _watchdogGeneration == _playGeneration) {
      return;
    }

    _cancelBufferingWatchdog();
    final songId = song.id;
    final generation = _playGeneration;
    _watchdogSongId = songId;
    _watchdogGeneration = generation;
    _bufferingWatchdog = Timer(_bufferingTimeout, () {
      _bufferingWatchdog = null;
      _watchdogSongId = null;
      _watchdogGeneration = -1;
      if (generation != _playGeneration ||
          _currentSong?.id != songId ||
          _playbackError != null) {
        return;
      }
      final state = _audio.player.processingState;
      final stillStalled = state == ProcessingState.loading ||
          state == ProcessingState.buffering;
      if (!stillStalled ||
          !_audio.player.playing ||
          _isResolving ||
          _isRecovering) {
        return;
      }
      unawaited(_recoverStalledPlayback(songId, generation));
    });
  }

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
    _cancelBufferingWatchdog();
    _playbackError = null;
    final requestedIndex = initialIndex.clamp(0, songs.length - 1).toInt();
    final requestedSong = songs[requestedIndex];
    _fallbackAttempts.remove(requestedSong.id);
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
      _recommendations.clear();
      _recommendationReasons.clear();
      _currentIndex = 0;
      _currentSong = first.song;
      _position = Duration.zero;
      _duration = first.song.duration ?? Duration.zero;
      if (_audio.player.playing) await _audio.player.pause();
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
      unawaited(
        _fillQueueThenRecommendations(
          songs,
          requestedIndex,
          generation,
          first.song,
        ),
      );
    } finally {
      if (generation == _playGeneration) {
        _isResolving = false;
        _refreshBufferingWatchdog();
      }
      notifyListeners();
    }
  }

  Future<void> _fillQueueThenRecommendations(
    List<SongModel> songs,
    int startIndex,
    int generation,
    SongModel seed,
  ) async {
    await _fillRemainingQueue(songs, startIndex, generation);
    if (generation != _playGeneration) return;
    await _appendRecommendations(seed, generation);
  }

  /// YouTube-style autoplay: after the user's own queue is safely in place,
  /// line up a small set of related songs so playback can keep flowing.
  ///
  /// This is deliberately additive and best-effort. Search or stream failures
  /// are logged and swallowed here; they must never interrupt the song that
  /// is already playing or replace anything the user explicitly queued.
  Future<void> _appendRecommendations(SongModel seed, int generation) async {
    if (_settings?.autoplayRecommendations == false || seed.isLiveStream) {
      return;
    }

    try {
      final candidates = await _gatherRecommendationCandidates(seed);
      if (generation != _playGeneration) return;

      final affinity = _recommendationArtistAffinity(seed);
      final recentSongs = _library.recentSongs;
      final recentlyPlayed = recentSongs.take(18).toList(growable: false);
      final previousIds = _usage.recentRecommendationIds.take(80).toSet();
      final recommendationCounts = _usage.recommendationCounts;
      final common = (
        seed: seed,
        excludedIds: _queue.map((song) => song.id).toSet(),
        excludedTitleKeys: _queue
            .map((song) => RecommendationEngine.canonicalTitleKey(song.title))
            .toSet(),
        recentlyPlayedIds: recentlyPlayed.map((song) => song.id).toSet(),
        recentTitleKeys: recentlyPlayed
            .map((song) => RecommendationEngine.canonicalTitleKey(song.title))
            .toSet(),
        artistAffinity: affinity.scores,
        recommendationCounts: recommendationCounts,
        preferredLanguages: <String>{
          if (seed.language.trim().isNotEmpty) seed.language.trim(),
          ...?_settings?.languages,
        },
        style: _settings?.recommendationStyle ?? 'balanced',
      );

      var ranked = RecommendationEngine.rank(
        candidates: candidates,
        seed: common.seed,
        excludedIds: common.excludedIds,
        excludedTitleKeys: common.excludedTitleKeys,
        recentlyPlayedIds: common.recentlyPlayedIds,
        recentTitleKeys: common.recentTitleKeys,
        previouslyRecommendedIds: previousIds,
        artistAffinity: common.artistAffinity,
        recommendationCounts: common.recommendationCounts,
        preferredLanguages: common.preferredLanguages,
        style: common.style,
      );
      if (ranked.isEmpty && previousIds.isNotEmpty) {
        // The rotation memory is there to avoid repeats, not to starve the
        // radio when the local catalogue pool is small. Fall back to older
        // recommendations while still excluding the queue, fresh recents,
        // and any song that has already reached the three-recommendation cap.
        ranked = RecommendationEngine.rank(
          candidates: candidates,
          seed: common.seed,
          excludedIds: common.excludedIds,
          excludedTitleKeys: common.excludedTitleKeys,
          recentlyPlayedIds: common.recentlyPlayedIds,
          recentTitleKeys: common.recentTitleKeys,
          previouslyRecommendedIds: const <String>{},
          artistAffinity: common.artistAffinity,
          recommendationCounts: common.recommendationCounts,
          preferredLanguages: common.preferredLanguages,
          style: common.style,
        );
      }

      var appended = 0;
      for (final recommendation in ranked) {
        if (generation != _playGeneration || appended >= 8) break;
        final failures = <String>[];
        final track =
            await _resolveTrack(recommendation.song, failures: failures);
        if (generation != _playGeneration) return;
        if (track == null) {
          logWarn('player', 'recommendation skipped', <String, Object?>{
            'song': recommendation.song.title,
            'reasons': failures.join(' | '),
          });
          continue;
        }
        _queue.add(track.song);
        _sources.add(track.source);
        // Publish the automatic origin before append: playback may already be
        // at the queue boundary and advance as soon as the source is added.
        _recommendations.add(track.song);
        _recommendationReasons[track.song.id] = recommendation.reason;
        try {
          await _audio.append(track.source);
        } catch (_) {
          _queue.removeLast();
          _sources.removeLast();
          _recommendations.removeWhere((song) => song.id == track.song.id);
          _recommendationReasons.remove(track.song.id);
          rethrow;
        }
        unawaited(_usage.recordSongEvent('recommendation', track.song));
        appended++;
        notifyListeners();
      }

      if (appended > 0) {
        logInfo('player', 'autoplay recommendations added', <String, Object?>{
          'seed': seed.title,
          'count': appended,
          'candidates': candidates.length,
          'style': common.style,
        });
      } else {
        logInfo('player', 'no fresh autoplay recommendations', <String, Object?>{
          'seed': seed.title,
          'candidates': candidates.length,
        });
      }
    } catch (error) {
      // Recommendations are optional. Playback must continue unchanged.
      logWarn('player', 'autoplay recommendations failed', <String, Object?>{
        'seed': seed.title,
        'error': '$error',
      });
    }
  }

  /// Builds a Spotify-style candidate pool instead of searching for the seed
  /// title again. Lanes: seed/profile artists, favourites and repeated plays,
  /// album context, language charts, selected-language discovery and the
  /// listener's own previous searches.
  Future<List<RecommendationCandidate>> _gatherRecommendationCandidates(
    SongModel seed,
  ) async {
    final tasks = <Future<List<RecommendationCandidate>>>[];

    void addSongs(
      Future<List<SongModel>> future,
      String lane, {
      double laneBoost = 0,
    }) {
      tasks.add(
        future.then<List<RecommendationCandidate>>(
          (songs) => songs
              .map(
                (song) => RecommendationCandidate(
                  song: song,
                  lane: lane,
                  laneBoost: laneBoost,
                ),
              )
              .toList(growable: false),
        ).catchError((Object _) => const <RecommendationCandidate>[]),
      );
    }

    final affinity = _recommendationArtistAffinity(seed);
    for (final artist in affinity.topArtists.take(6)) {
      addSongs(
        _musicApi.searchSaavnWithYouTubeFallback('$artist songs', limit: 18),
        'artist',
        laneBoost: 3,
      );
    }
    if (seed.source == SongSource.youtube) {
      addSongs(
        _musicApi.searchYouTube('${seed.artist} songs', limit: 16),
        'artist',
        laneBoost: 2,
      );
    }

    final languages = <String>{
      if (seed.language.trim().isNotEmpty) seed.language.trim().toLowerCase(),
      ...?_settings?.languages.map((value) => value.toLowerCase()),
    };
    for (final language in languages.take(3)) {
      addSongs(
        _musicApi.fetchTrending(language: language, limit: 20),
        'trending',
        laneBoost: 2,
      );
    }

    for (final search in _usage.topSearches.take(2)) {
      addSongs(
        _musicApi.searchSaavnWithYouTubeFallback(search.query, limit: 16),
        'search',
        laneBoost: 1,
      );
    }

    if (seed.source == SongSource.jioSaavn &&
        seed.album.trim().isNotEmpty &&
        RecommendationEngine.canonicalTitleKey(seed.album) !=
            RecommendationEngine.canonicalTitleKey(seed.title)) {
      tasks.add(() async {
        try {
          final albums = await _musicApi.searchAlbums(seed.album, limit: 5);
          AlbumSummary? match;
          for (final album in albums) {
            if (RecommendationEngine.canonicalTitleKey(album.title) ==
                RecommendationEngine.canonicalTitleKey(seed.album)) {
              match = album;
              break;
            }
          }
          if (match == null) return const <RecommendationCandidate>[];
          final songs = await _musicApi.fetchAlbumSongs(
            match.id,
            albumTitle: match.title,
            albumArtist: match.artist,
            limit: 30,
          );
          return songs
              .map(
                (song) => RecommendationCandidate(
                  song: song,
                  lane: 'album',
                  laneBoost: 2,
                ),
              )
              .toList(growable: false);
        } catch (_) {
          return const <RecommendationCandidate>[];
        }
      }());
    }

    final groups = await Future.wait(tasks);
    return groups.expand((group) => group).toList(growable: false);
  }

  _ArtistAffinity _recommendationArtistAffinity(SongModel seed) {
    final scores = <String, double>{};
    final displayNames = <String, String>{};

    void addArtist(String display, double weight) {
      final key = RecommendationEngine.normalise(display);
      if (key.isEmpty || key == 'unknown' || key == 'unknown artist') return;
      displayNames.putIfAbsent(key, () => display.trim());
      scores[key] = (scores[key] ?? 0) + weight;
    }

    void addSong(SongModel song, double weight) {
      for (final artist in RecommendationEngine.artistsOf(song)) {
        addArtist(artist, weight);
      }
    }

    addSong(seed, 7);
    for (final song in _queue) {
      addSong(song, 2.2);
    }
    for (final song in _library.favoriteSongs) {
      addSong(song, 5);
    }
    for (final song in _library.downloadedSongs) {
      addSong(song, 3);
    }
    final recents = _library.recentSongs;
    for (var index = 0; index < recents.length; index++) {
      addSong(recents[index], index < 5 ? 4 : (index < 15 ? 2.4 : 1.1));
    }
    for (final track in _usage.topTracks) {
      for (final artist in RecommendationEngine.artistNames(track.artist)) {
        addArtist(artist, 2 + track.plays.clamp(0, 12).toDouble() * 0.55);
      }
    }

    final rankedKeys = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return _ArtistAffinity(
      scores: Map<String, double>.unmodifiable(scores),
      topArtists: rankedKeys
          .map((key) => displayNames[key]!)
          .toList(growable: false),
    );
  }

  /// Starts playback at an existing queue position (used by Up next).
  Future<void> playAtQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    // A listener selecting a suggested queue item turns it into an explicit
    // play, so subsequent history belongs in Recent Activity, not autoplay.
    final selected = _queue[index];
    _recommendationReasons.remove(selected.id);
    _recommendations.removeWhere((song) => song.id == selected.id);
    try {
      await _audio.player.seek(Duration.zero, index: index);
      if (!_audio.player.playing) _startPlayback();
      notifyListeners();
    } on PlayerException {
      // The queue may be changing while recommendations are being appended.
    } on StateError {
      // Ignore a transient empty/changing queue.
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
      if (_playbackError != null) {
        await retryCurrentPlayback();
      } else {
        _startPlayback();
      }
    }
    notifyListeners();
  }

  /// Retries the selected result from its stable ID instead of reusing a
  /// possibly expired or unresponsive media URL.
  Future<void> retryCurrentPlayback() async {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    _musicApi.invalidateStream(song.id);
    _fallbackAttempts.remove(song.id);
    final songs = List<SongModel>.of(_queue);
    songs[index] = song.copyWith(streamUrl: '');
    _playbackError = null;
    try {
      await playQueue(songs, initialIndex: index);
    } catch (error) {
      _failCurrentPlayback(
        song.id,
        'Could not reload this track. Check your connection or choose another result.',
      );
      logWarn('player', 'manual stream retry failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
    }
  }

  /// Pauses playback (used by the sleep timer).
  Future<void> pause() async {
    if (!_audio.player.playing) return;
    logInfo('player', 'paused by sleep timer');
    await _audio.player.pause();
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
    // Previous always follows the queue/shuffle order, even when the current
    // track is well underway. Restarting the current song belongs to tapping
    // its artwork/progress, not to the dedicated Previous control.
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

  static bool nextShuffleState(bool enabled) => !enabled;

  static LoopMode nextRepeatMode(LoopMode mode) => switch (mode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      };

  static String repeatModeLabel(LoopMode mode) => switch (mode) {
        LoopMode.off => 'Repeat off',
        LoopMode.all => 'Repeat all',
        LoopMode.one => 'Repeat 1',
      };

  static String repeatModeDescription(LoopMode mode) => switch (mode) {
        LoopMode.off => 'Repeat is off',
        LoopMode.all =>
          'Repeat every track in the queue, then start the queue again',
        LoopMode.one => 'Repeat the current track until you choose another mode',
      };

  Future<void> toggleShuffle() async {
    final next = nextShuffleState(_shuffleEnabled);
    await _audio.player.setShuffleModeEnabled(next);
    _shuffleEnabled = next;
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    final next = nextRepeatMode(_loopMode);
    await _audio.player.setLoopMode(next);
    _loopMode = next;
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
    // The user explicitly cleared what was coming next, including any
    // autoplay recommendations MuZic had lined up.
    _recommendations.clear();
    _recommendationReasons.clear();
    _currentSong = keepSong;
    _currentIndex = 0;
    if (wasPlaying) await _audio.player.pause();
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
    _downloadCancelRequested = false;
    final cancelSignal = Completer<void>();
    _downloadCancelSignal = cancelSignal;
    notifyListeners();

    Future<String> resolveWhileActive(Future<String> pending) async {
      final resolved = await Future.any<String?>(<Future<String?>>[
        pending.then<String?>((value) => value),
        cancelSignal.future.then<String?>((_) => null),
      ]);
      if (_downloadCancelRequested || resolved == null) {
        throw const DownloadCancelledException();
      }
      return resolved;
    }

    try {
      final streamUrl = await resolveWhileActive(_musicApi.resolveStream(song));
      try {
        await _downloads.downloadSong(
          song,
          streamUrl,
          onProgress: (value) {
            _downloadProgress = value;
            notifyListeners();
          },
          isCancelled: () => _downloadCancelRequested,
        );
      } catch (error) {
        if (error is DownloadCancelledException || _downloadCancelRequested) {
          throw const DownloadCancelledException();
        }
        if (song.source != SongSource.jioSaavn) rethrow;
        final fallbackUrl = await resolveWhileActive(
          _musicApi.resolveYouTubeFallback(song),
        );
        await _downloads.downloadSong(
          song.copyWith(streamUrl: fallbackUrl),
          fallbackUrl,
          onProgress: (value) {
            _downloadProgress = value;
            notifyListeners();
          },
          isCancelled: () => _downloadCancelRequested,
        );
      }
      if (_downloadCancelRequested) throw const DownloadCancelledException();
      await _usage.recordSongEvent('download', song);
      logInfo('player', 'download finished', <String, Object?>{
        'song': song.title,
      });
    } catch (error) {
      if (error is DownloadCancelledException || _downloadCancelRequested) {
        logInfo('player', 'download cancelled', <String, Object?>{
          'song': song.title,
        });
        throw const DownloadCancelledException();
      }
      logError('player', 'download failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
      rethrow;
    } finally {
      _downloadingId = null;
      _downloadProgress = 0;
      _downloadCancelRequested = false;
      _downloadCancelSignal = null;
      notifyListeners();
    }
  }

  Future<void> cancelDownload([String? songId]) async {
    final activeId = _downloadingId;
    if (activeId == null || (songId != null && songId != activeId)) return;
    _downloadCancelRequested = true;
    final cancelSignal = _downloadCancelSignal;
    if (cancelSignal != null && !cancelSignal.isCompleted) {
      cancelSignal.complete();
    }
    _downloads.cancelDownload(activeId);
    notifyListeners();
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
      logWarn('player', 'track resolver failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
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

  void _recordPlaybackStart(
    SongModel song, {
    bool isRecommendation = false,
  }) {
    if (_lastUsageTrackId == song.id) return;
    _lastUsageTrackId = song.id;
    unawaited(_usage.recordSongEvent(
      isRecommendation ? 'recommendation_play' : 'play',
      song,
    ));
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
    if (_isRecovering || _playbackError != null) return;
    final song = _currentSong;
    if (song == null) return;
    unawaited(_recoverStalledPlayback(song.id, _playGeneration));
  }

  Future<void> _recoverStalledPlayback(String songId, int generation) async {
    if (generation != _playGeneration ||
        _currentSong?.id != songId ||
        _isRecovering ||
        _playbackError != null) {
      return;
    }
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    final attempts = _fallbackAttempts.putIfAbsent(song.id, () => <String>{});
    final action = nextPlaybackRecoveryAction(song: song, attempts: attempts);
    logWarn('player', 'trying bounded stream recovery', <String, Object?>{
      'song': song.title,
      'action': action.name,
    });

    switch (action) {
      case PlaybackRecoveryAction.lowerSourceAQuality:
        attempts.add('quality');
        final url = (song.streamUrl ?? '').replaceFirst('_320.mp4', '_96.mp4');
        await _replaceCurrentSource(
          song,
          index,
          url,
          label: 'source-a-96-after-stall',
          generation: generation,
        );
        break;
      case PlaybackRecoveryAction.refreshSourceA:
        attempts.add('source-a-refresh');
        await _refreshSourceA(song, index, generation, attempts);
        break;
      case PlaybackRecoveryAction.lowerSourceBBitrate:
        attempts.add('youtube-low');
        await _recoverWithLowerBitrate(song, index, generation);
        break;
      case PlaybackRecoveryAction.alternateSource:
        attempts.add('youtube');
        await _recoverCurrentWithYouTube(
          song,
          index,
          generation: generation,
        );
        break;
      case PlaybackRecoveryAction.stop:
        _failCurrentPlayback(
          song.id,
          'This stream is not responding. Tap Retry or choose another result.',
        );
        break;
    }
  }

  Future<void> _refreshSourceA(
    SongModel song,
    int index,
    int generation,
    Set<String> attempts,
  ) async {
    String? url;
    Object? failure;
    _isRecovering = true;
    _cancelBufferingWatchdog();
    notifyListeners();
    try {
      _musicApi.invalidateStream(song.id);
      url = await _musicApi.refreshSourceAStream(
        song,
        preferLowerBitrate: attempts.contains('quality'),
      );
    } catch (error) {
      failure = error;
      logWarn('player', 'Source A stream refresh failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
    } finally {
      _isRecovering = false;
      _refreshBufferingWatchdog();
      notifyListeners();
    }

    if (!_isCurrentRecoveryTarget(song.id, index, generation)) return;
    if (url == null || failure != null) {
      await _recoverStalledPlayback(song.id, generation);
      return;
    }
    await _replaceCurrentSource(
      song,
      index,
      url,
      label: 'source-a-refreshed',
      generation: generation,
    );
  }

  Future<void> _recoverWithLowerBitrate(
    SongModel song,
    int index,
    int generation,
  ) async {
    String? url;
    Object? failure;
    _isRecovering = true;
    _cancelBufferingWatchdog();
    notifyListeners();
    try {
      url = await _musicApi.resolveYouTube(song, lowestBitrate: true);
    } catch (error) {
      failure = error;
      logWarn('player', 'lower-bitrate stream lookup failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
    } finally {
      _isRecovering = false;
      _refreshBufferingWatchdog();
      notifyListeners();
    }

    if (!_isCurrentRecoveryTarget(song.id, index, generation)) return;
    if (url == null || failure != null) {
      await _recoverStalledPlayback(song.id, generation);
      return;
    }
    await _replaceCurrentSource(
      song,
      index,
      url,
      label: 'source-b-low-bitrate',
      generation: generation,
    );
  }

  Future<void> _replaceCurrentSource(
    SongModel song,
    int index,
    String url, {
    required String label,
    int? generation,
  }) async {
    if (!_isCurrentRecoveryTarget(song.id, index, generation)) return;
    _isRecovering = true;
    _cancelBufferingWatchdog();
    notifyListeners();
    String? failure;
    try {
      final fallbackSong = song.copyWith(streamUrl: url);
      _queue[index] = fallbackSong;
      _sources[index] = _audio.sourceFor(fallbackSong, remoteUrl: url);
      if (_currentSong?.id == song.id) _currentSong = fallbackSong;
      if (_audio.player.playing) await _audio.player.pause();
      await _audio.setQueue(
        _sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      if (!_isCurrentRecoveryTarget(song.id, index, generation)) return;
      _position = Duration.zero;
      _playbackError = null;
      _startPlayback();
      logInfo('player', 'fallback applied', <String, Object?>{
        'song': song.title,
        'via': label,
      });
    } catch (fallbackError) {
      failure = '$fallbackError';
      logError(
        'player',
        'fallback source could not be installed',
        <String, Object?>{
          'song': song.title,
          'via': label,
          'error': failure,
        },
      );
    } finally {
      _isRecovering = false;
      _refreshBufferingWatchdog();
      notifyListeners();
    }
    if (failure != null && _isCurrentRecoveryTarget(song.id, index, generation)) {
      final attempts = _fallbackAttempts.putIfAbsent(song.id, () => <String>{});
      if (!attempts.contains('youtube')) {
        attempts.add('youtube');
        await _recoverCurrentWithYouTube(
          song,
          index,
          generation: generation,
        );
      } else {
        _failCurrentPlayback(
          song.id,
          'This stream could not be started. Tap Retry or choose another result.',
        );
      }
    }
  }

  Future<void> _recoverCurrentWithYouTube(
    SongModel song,
    int index, {
    int? generation,
  }) async {
    if (!_isCurrentRecoveryTarget(song.id, index, generation)) return;
    String? url;
    Object? failure;
    _isRecovering = true;
    _cancelBufferingWatchdog();
    notifyListeners();
    try {
      url = await _musicApi.resolveYouTubeFallback(
        song,
        lowestBitrate: true,
      );
    } catch (error) {
      failure = error;
      logError('player', 'Source B fallback failed', <String, Object?>{
        'song': song.title,
        'error': '$error',
      });
    } finally {
      _isRecovering = false;
      _refreshBufferingWatchdog();
      notifyListeners();
    }

    if (!_isCurrentRecoveryTarget(song.id, index, generation)) return;
    if (url == null || failure != null) {
      _failCurrentPlayback(
        song.id,
        'No working stream was found. Tap Retry or choose another result.',
      );
      return;
    }
    await _replaceCurrentSource(
      song,
      index,
      url,
      label: 'source-b-fallback',
      generation: generation,
    );
  }

  bool _isCurrentRecoveryTarget(String songId, int index, int? generation) =>
      (generation == null || generation == _playGeneration) &&
      _currentSong?.id == songId &&
      _currentIndex == index &&
      index >= 0 &&
      index < _queue.length;

  void _failCurrentPlayback(String songId, String message) {
    if (_currentSong?.id != songId) return;
    _playbackError = message;
    _cancelBufferingWatchdog();
    logError('player', 'stream recovery exhausted', <String, Object?>{
      'song': _currentSong?.title,
      'message': message,
    });
    unawaited(_audio.player.pause().catchError((Object error) {
      logDebug('player', 'pause after stream failure did not complete',
          <String, Object?>{'error': '$error'});
    }));
    notifyListeners();
  }

  @override
  void dispose() {
    _playGeneration++;
    _cancelBufferingWatchdog();
    _flushListeningTime();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _musicApi.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }

}

class _ArtistAffinity {
  const _ArtistAffinity({required this.scores, required this.topArtists});

  final Map<String, double> scores;
  final List<String> topArtists;
}

class _ResolvedTrack {
  const _ResolvedTrack(this.song, this.source);

  final SongModel song;
  final AudioSource source;
}
