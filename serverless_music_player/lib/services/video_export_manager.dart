import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyrics_model.dart';
import '../models/song_model.dart';
import 'app_log.dart';
import 'video_export_service.dart';

/// Lifecycle of a lyric-video render.
enum VideoExportState { idle, preparing, rendering, saving, done, failed }

/// App-wide owner of the "export lyric video" job.
///
/// The render used to live inside the now-playing sheet, so closing the sheet
/// lost the job or froze the UI behind a modal dialog. It now runs here: the
/// sheet can be dismissed, the user can keep browsing, and the percentage stays
/// visible on the export button. Tapping that percentage offers "Stop".
class VideoExportManager extends ChangeNotifier {
  VideoExportManager({VideoExportService? service})
      : _service = service ?? VideoExportService();

  final VideoExportService _service;

  VideoExportState _state = VideoExportState.idle;
  double _progress = 0;
  String? _songTitle;
  SongModel? _song;
  VideoExportResult? _lastResult;
  String? _error;
  bool _cancelRequested = false;
  Completer<void> _cancelSignal = Completer<void>();
  bool _isRendering = false;
  String? _preparedAudioPath;
  Future<void> Function()? _cancelPreparation;
  Future<void> Function(String path)? _cleanupAudio;
  StreamSubscription<double>? _progressSubscription;

  VideoExportState get state => _state;
  double get progress => _progress;
  int get percent => (_progress * 100).round();
  String? get songTitle => _songTitle;
  VideoExportResult? get lastResult => _lastResult;
  String? get error => _error;

  /// True while a render is in flight (preparing, rendering or saving).
  bool get isBusy =>
      _state == VideoExportState.preparing ||
      _state == VideoExportState.rendering ||
      _state == VideoExportState.saving;

  /// The song currently being rendered, if any.
  SongModel? get currentSong => isBusy ? _song : null;

  Future<VideoExportResult?> start({
    required SongModel song,
    required Future<String> Function(
      void Function(double progress) onProgress,
      bool Function() isCancelled,
    ) prepareAudio,
    required Future<LyricsModel?> Function() loadLyrics,
    Future<void> Function()? cancelPreparation,
    Future<void> Function(String path)? cleanupAudio,
  }) async {
    if (isBusy) return null;
    _song = song;
    _songTitle = song.title;
    _error = null;
    _lastResult = null;
    _progress = 0;
    _cancelRequested = false;
    _cancelSignal = Completer<void>();
    _isRendering = false;
    _preparedAudioPath = null;
    _cancelPreparation = cancelPreparation;
    _cleanupAudio = cleanupAudio;
    _state = VideoExportState.preparing;
    notifyListeners();

    await _progressSubscription?.cancel();
    try {
      if (_cancelRequested) {
        _reset();
        return null;
      }
      final prepareFuture = prepareAudio((value) {
        if (!isBusy || _cancelRequested) return;
        final preparationProgress = value.clamp(0.0, 1.0).toDouble() * 0.4;
        if (preparationProgress > _progress) {
          _progress = preparationProgress;
          notifyListeners();
        }
      }, () => _cancelRequested);
      final audioPath = await Future.any<String?>(<Future<String?>>[
        prepareFuture.then<String?>((path) => path),
        _cancelSignal.future.then<String?>((_) => null),
      ]);
      if (audioPath == null) {
        // A resolver may finish after its cancel signal. If it produced a
        // temporary file late, remove it rather than leaving it behind.
        unawaited(
          prepareFuture.then<void>(
            (latePath) async {
              try {
                await cleanupAudio?.call(latePath);
              } catch (error) {
                logWarn('video', 'late temporary audio cleanup failed',
                    <String, Object?>{'error': '$error'});
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              logWarn('video', 'audio preparation ended after cancellation',
                  <String, Object?>{
                    'error': '$error',
                    'stack': '$stackTrace',
                  });
            },
          ),
        );
        _reset();
        return null;
      }
      _preparedAudioPath = audioPath;
      if (_cancelRequested) {
        _reset();
        return null;
      }

      // Keep one continuous percentage across audio preparation and encoding.
      _progress = _progress < 0.4 ? 0.4 : _progress;
      notifyListeners();
      final lyricsFuture = loadLyrics();
      final lyrics = await Future.any<LyricsModel?>(<Future<LyricsModel?>>[
        lyricsFuture,
        _cancelSignal.future.then<LyricsModel?>((_) => null),
      ]);
      if (_cancelRequested) {
        _reset();
        return null;
      }

      _state = VideoExportState.rendering;
      _isRendering = true;
      _progress = _progress < 0.42 ? 0.42 : _progress;
      _progressSubscription = _service.progress.listen((value) {
        if (!isBusy || !_isRendering) return;
        final renderProgress = 0.42 +
            value.clamp(0.0, 1.0).toDouble() * 0.58;
        if (renderProgress >= _progress) {
          _progress = renderProgress.clamp(0.0, 1.0).toDouble();
          notifyListeners();
        }
      });
      notifyListeners();

      final result = await _service.export(
        song: song,
        audioPath: audioPath,
        lyrics: lyrics,
        isCancelled: () => _cancelRequested,
      );
      if (_cancelRequested) {
        _reset();
        return null;
      }
      _lastResult = result;
      _progress = 1;
      _state = VideoExportState.done;
      logInfo('video', 'export finished', <String, Object?>{
        'song': song.title,
        'path': result.path,
      });
      notifyListeners();
      return result;
    } catch (error) {
      if (_cancelRequested) {
        logInfo('video', 'export cancelled', <String, Object?>{'song': song.title});
        _reset();
      } else {
        logError('video', 'export failed', <String, Object?>{
          'song': song.title,
          'error': '$error',
        });
        _state = VideoExportState.failed;
        _error = error is StateError ? error.message : '$error';
        _song = null;
        _songTitle = null;
        notifyListeners();
      }
      return null;
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      _isRendering = false;
      final audioPath = _preparedAudioPath;
      _preparedAudioPath = null;
      if (audioPath != null) {
        try {
          await _cleanupAudio?.call(audioPath);
        } catch (error) {
          logWarn('video', 'temporary audio cleanup failed', <String, Object?>{
            'error': '$error',
          });
        }
      }
      _cancelPreparation = null;
      _cleanupAudio = null;
    }
  }

  void _reset() {
    _state = VideoExportState.idle;
    _progress = 0;
    _song = null;
    _songTitle = null;
    _error = null;
    notifyListeners();
  }

  /// Stops preparation, lyric lookup, or rendering for the active export.
  /// During rendering, the encoder aborts at the next frame boundary.
  Future<void> cancel() async {
    if (!isBusy) return;
    _cancelRequested = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
    try {
      if (_isRendering) {
        await _service.cancel();
      } else {
        await _cancelPreparation?.call();
      }
    } catch (error) {
      logWarn('video', 'cancel request failed', <String, Object?>{'error': '$error'});
    }
    notifyListeners();
  }

  /// Clears a finished or failed state so the UI returns to its idle look.
  void acknowledge() {
    if (isBusy) return;
    _reset();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }
}
