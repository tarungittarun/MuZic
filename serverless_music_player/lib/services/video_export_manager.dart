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
    required String audioPath,
    required LyricsModel? lyrics,
  }) async {
    if (isBusy) return null;
    _song = song;
    _songTitle = song.title;
    _error = null;
    _lastResult = null;
    _progress = 0;
    _cancelRequested = false;
    _state = VideoExportState.preparing;
    notifyListeners();

    await _progressSubscription?.cancel();
    _progressSubscription = _service.progress.listen((value) {
      if (!isBusy) return;
      if (value >= _progress) {
        _progress = value.clamp(0.0, 1.0);
        if (_state == VideoExportState.preparing) {
          _state = VideoExportState.rendering;
        }
        notifyListeners();
      }
    });

    try {
      final result = await _service.export(
        song: song,
        audioPath: audioPath,
        lyrics: lyrics,
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

  /// Asks the renderer to stop; the encoder aborts at the next frame boundary.
  Future<void> cancel() async {
    if (!isBusy) return;
    _cancelRequested = true;
    try {
      await _service.cancel();
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
