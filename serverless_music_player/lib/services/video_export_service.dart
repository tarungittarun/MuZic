import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/lyrics_model.dart';
import '../models/song_model.dart';
import '../utils/file_name_utils.dart';
import 'app_log.dart';

/// Result of a finished lyric-video export.
class VideoExportResult {
  const VideoExportResult({required this.path, required this.shared});

  /// A MediaStore or SAF URI (`content://…`) on Android, or a file path.
  final String path;
  final bool shared;
}

/// Exports a shareable lyric video: cover art, live waveform and synced lyrics
/// rendered and encoded on device by platform MediaCodec.
class VideoExportService {
  VideoExportService({MethodChannel? channel, EventChannel? progressChannel})
      : _channel = channel ?? const MethodChannel('music_player/video_export'),
        _progressChannel = progressChannel ??
            const EventChannel('music_player/video_export_progress');

  final MethodChannel _channel;
  final EventChannel _progressChannel;
  CancelToken? _artworkCancelToken;
  bool _cancelRequested = false;

  Stream<double> get progress => _progressChannel
      .receiveBroadcastStream()
      .map((dynamic event) => (event as num).toDouble());

  /// Renders [song] into an MP4 using [audioPath] as the soundtrack and
  /// [lyrics] for the captions. [onProgress] receives 0..1.
  Future<VideoExportResult> export({
    required SongModel song,
    required String audioPath,
    required LyricsModel? lyrics,
    String? outputFolderUri,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();
    var stage = 'validate_lyrics';
    if (lyrics == null || !lyrics.hasSynced) {
      logError('video', 'export input validation failed', <String, Object?>{
        'song': song.title,
        'stage': stage,
        'progressPercent': 40,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': 'Lyrics are unavailable for this track.',
      });
      throw StateError('Lyrics are unavailable for this track.');
    }
    _cancelRequested = false;
    final artworkCancelToken = CancelToken();
    _artworkCancelToken = artworkCancelToken;
    StreamSubscription<double>? subscription;
    try {
      stage = 'download_artwork';
      logInfo('video', 'export stage', <String, Object?>{
        'song': song.title,
        'stage': stage,
        'progressPercent': 40,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      final artworkPath = await _downloadArtwork(
        song,
        cancelToken: artworkCancelToken,
      );
      if (_cancelRequested || isCancelled?.call() == true) {
        throw StateError('Export stopped.');
      }
      stage = 'media_export';
      logInfo('video', 'export stage', <String, Object?>{
        'song': song.title,
        'stage': stage,
        'progressPercent': 42,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'lyricLineCount': lyrics.syncedLines.length,
        'hasArtwork': artworkPath != null,
      });
      final lines = <Map<String, Object?>>[
        for (final line in lyrics.syncedLines)
          <String, Object?>{
            'timeMs': line.time.inMilliseconds,
            'text': line.text,
          },
      ];
      subscription = onProgress == null
          ? null
          : progress.listen((value) => onProgress(value));
      if (_cancelRequested || isCancelled?.call() == true) {
        throw StateError('Export stopped.');
      }

      final path = await _channel.invokeMethod<String>(
        'export',
        <String, Object?>{
          'audioPath': audioPath,
          'artworkPath': artworkPath,
          'title': song.title,
          'artist': song.artist,
          'durationMs': song.duration?.inMilliseconds ??
              (lyrics.syncedLines.last.time.inMilliseconds + 6000),
          'lyrics': jsonEncode(lines),
          'outputName': _outputName(song),
          'outputFolderUri': outputFolderUri,
        },
      );
      logInfo('video', 'export finished', <String, Object?>{
        'song': song.title,
        'stage': 'completed',
        'progressPercent': 100,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'path': path,
        'lyricLines': lines.length,
      });
      return VideoExportResult(path: path ?? '', shared: path != null);
    } on MissingPluginException catch (error) {
      logError('video', 'export failed', <String, Object?>{
        'song': song.title,
        'stage': stage,
        'progressPercent': 42,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': '$error',
      });
      throw StateError('Video export is unavailable on this device.');
    } on PlatformException catch (error) {
      final details = error.details;
      final detailMap = details is Map ? details : const <Object?, Object?>{};
      final rawProgress = detailMap['progress'];
      logError('video', 'export failed', <String, Object?>{
        'song': song.title,
        'stage': detailMap['stage']?.toString() ?? stage,
        'progressPercent': rawProgress is num ? (rawProgress * 100).round() : 42,
        'elapsedMs': detailMap['elapsedMs'] is num
            ? detailMap['elapsedMs']
            : stopwatch.elapsedMilliseconds,
        'errorCode': error.code,
        'error': error.message ?? '$error',
        'nativeDetails': details,
      });
      throw StateError(error.message ?? 'Video export failed.');
    } catch (error) {
      logError('video', 'export failed', <String, Object?>{
        'song': song.title,
        'stage': stage,
        'progressPercent': 42,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': '$error',
      });
      rethrow;
    } finally {
      await subscription?.cancel();
      if (identical(_artworkCancelToken, artworkCancelToken)) {
        _artworkCancelToken = null;
      }
    }
  }

  /// Stops an in-flight render or artwork download. The native side aborts at
  /// the next frame and deletes the partial file.
  Future<void> cancel() async {
    _cancelRequested = true;
    _artworkCancelToken?.cancel('Stopped by the user.');
    await _channel.invokeMethod<void>('cancelExport');
  }

  String _outputName(SongModel song) => trackFileBase(song.title);

  /// Caches the cover art locally so the encoder can draw it.
  Future<String?> _downloadArtwork(
    SongModel song, {
    required CancelToken cancelToken,
  }) async {
    final local = song.localArtworkPath;
    if (local != null && File(local).existsSync()) return local;
    final url = song.artworkUrl;
    if (url.isEmpty) return null;
    try {
      final directory = Directory(
        p.join((await getTemporaryDirectory()).path, 'video_artwork'),
      );
      if (!directory.existsSync()) directory.createSync(recursive: true);
      final artworkName = trackFileBase(song.title);
      final file = File(p.join(directory.path, '$artworkName.jpg'));
      if (file.existsSync() && await file.length() > 1024) return file.path;
      await Dio().download(url, file.path, cancelToken: cancelToken);
      return file.path;
    } catch (error) {
      logWarn('video', 'artwork download failed', <String, Object?>{
        'error': '$error',
      });
      return null;
    }
  }
}
