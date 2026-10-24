import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song_model.dart';
import '../utils/file_name_utils.dart';
import 'app_settings_service.dart';
import 'library_service.dart';
import 'local_files_service.dart';

/// Thrown when the user explicitly stops an audio transfer.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download stopped.';
}

class DownloadService {
  DownloadService({
    required LibraryService library,
    Dio? dio,
    AppSettingsService? settings,
    LocalFilesService? localFiles,
  })  : _library = library,
        _settings = settings,
        _localFiles = localFiles ?? LocalFilesService(),
        _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 12),
          sendTimeout: const Duration(seconds: 20),
          followRedirects: true,
          maxRedirects: 5,
        ));

  final LibraryService _library;
  final AppSettingsService? _settings;
  final LocalFilesService _localFiles;
  final Dio _dio;
  final Map<String, CancelToken> _activeTransfers = <String, CancelToken>{};

  void cancelDownload(String songId) =>
      _activeTransfers['download:$songId']?.cancel('Stopped by the user.');

  void cancelTemporaryAudioDownload(String songId) =>
      _activeTransfers['video:$songId']?.cancel('Stopped by the user.');

  Future<void> deleteTemporaryAudio(String path) async {
    final support = await getApplicationSupportDirectory();
    final exportDirectory =
        Directory(p.join(support.path, 'muzic_video_audio'));
    final normalizedPath = p.normalize(path);
    final normalizedDirectory = p.normalize(exportDirectory.path);
    if (!p.isWithin(normalizedDirectory, normalizedPath)) return;
    final file = File(normalizedPath);
    if (await file.exists()) await file.delete();
  }

  Future<bool> _localPathExists(String path) {
    if (path.startsWith('content://')) {
      // Android owns this file through scoped storage; ask its content resolver
      // rather than assuming an old URI still points to a readable file.
      return _localFiles.contentFileExists(path);
    }
    return File(path).exists();
  }

  Future<String?> localPathFor(String songId) async {
    final song = _library.downloadedSong(songId);
    final path = song?.localPath;
    if (path == null || path.isEmpty) return null;
    return await _localPathExists(path) ? path : null;
  }

  Future<SongModel> downloadSong(
    SongModel song,
    String streamUrl, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final existing = _library.downloadedSong(song.id);
    if (existing?.localPath != null &&
        await _localPathExists(existing!.localPath!)) {
      return existing;
    }
    if (isCancelled?.call() == true) {
      throw const DownloadCancelledException();
    }

    final root = await getApplicationDocumentsDirectory();
    final musicDirectory = Directory(p.join(root.path, 'music'));
    final artworkDirectory = Directory(p.join(musicDirectory.path, 'artwork'));
    await musicDirectory.create(recursive: true);
    await artworkDirectory.create(recursive: true);
    if (isCancelled?.call() == true) {
      throw const DownloadCancelledException();
    }

    final baseName = trackFileBase(song.title);
    final extension = _audioExtension(streamUrl);
    final usedNames = _library.downloadedSongs
        .where((saved) => saved.id != song.id)
        .map((saved) => trackFileBase(saved.title))
        .toSet();
    var uniqueBase = baseName;
    var suffix = 2;
    String pathForBase(String base) =>
        p.join(musicDirectory.path, '$base$extension');
    var outputPath = pathForBase(uniqueBase);
    while (usedNames.contains(uniqueBase) ||
        ((await File(outputPath).exists()) && existing?.localPath != outputPath)) {
      uniqueBase = '$baseName ($suffix)';
      suffix++;
      outputPath = pathForBase(uniqueBase);
    }
    if (isCancelled?.call() == true) {
      throw const DownloadCancelledException();
    }
    final partialPath = '$outputPath.part';
    final audioFile = File(partialPath);
    if (await audioFile.exists()) await audioFile.delete();
    final previousOutput = File(outputPath);
    if (await previousOutput.exists()) await previousOutput.delete();

    const transferKeyPrefix = 'download:';
    final transferKey = '$transferKeyPrefix${song.id}';
    final cancelToken = CancelToken();
    _activeTransfers[transferKey] = cancelToken;
    File? savedAudio;
    String? copiedPath;
    try {
      if (isCancelled?.call() == true) {
        throw const DownloadCancelledException();
      }
      onProgress?.call(0);
      await _dio.download(
        streamUrl,
        partialPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0).toDouble());
          }
        },
        deleteOnError: true,
        options: Options(
          headers: const <String, String>{'Accept': '*/*'},
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (cancelToken.isCancelled) throw const DownloadCancelledException();
      if (!await audioFile.exists() || await audioFile.length() == 0) {
        throw const FileSystemException('The downloaded audio file is empty.');
      }
      savedAudio = await audioFile.rename(outputPath);
      String? artworkPath;
      if (song.artworkUrl.startsWith('https://') ||
          song.artworkUrl.startsWith('http://')) {
        final imageExtension = _imageExtension(song.artworkUrl);
        final imageFile = File(
          p.join(artworkDirectory.path, '$uniqueBase$imageExtension'),
        );
        try {
          await _dio.download(
            song.artworkUrl,
            imageFile.path,
            cancelToken: cancelToken,
            deleteOnError: true,
            options: Options(
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
            ),
          );
          if (await imageFile.exists() && await imageFile.length() > 0) {
            artworkPath = imageFile.path;
          }
        } on DioException catch (error) {
          if (cancelToken.isCancelled || error.type == DioExceptionType.cancel) {
            rethrow;
          }
          artworkPath = null;
        } on FileSystemException {
          artworkPath = null;
        }
      }
      if (cancelToken.isCancelled) throw const DownloadCancelledException();

      var storedAudioPath = savedAudio.path;
      final customFolder = _settings;
      if (customFolder != null && customFolder.hasCustomDownloadsFolder) {
        // Copy the finished, original bytes into the user's folder. If the
        // folder grant is unavailable, keep the working app-storage copy
        // rather than failing a download that already succeeded.
        copiedPath = await _localFiles.copyFileToDownloadsFolder(
          folderUri: customFolder.downloadsFolderUri,
          sourcePath: savedAudio.path,
          fileName: p.basename(savedAudio.path),
          mimeType: _mimeTypeForExtension(extension),
        );
        if (copiedPath != null) {
          if (cancelToken.isCancelled) {
            await _localFiles.deleteSharedFile(copiedPath);
            throw const DownloadCancelledException();
          }
          storedAudioPath = copiedPath;
          if (await savedAudio.exists()) await savedAudio.delete();
        }
      }

      final savedSong = song.copyWith(
        localPath: storedAudioPath,
        localArtworkPath: artworkPath,
      );
      await _library.saveDownload(savedSong);
      onProgress?.call(1.0);
      return savedSong;
    } catch (error) {
      if (await audioFile.exists()) await audioFile.delete();
      if (savedAudio != null && await savedAudio.exists()) {
        await savedAudio.delete();
      }
      if (copiedPath != null) await _localFiles.deleteSharedFile(copiedPath);
      if (cancelToken.isCancelled ||
          (error is DioException && error.type == DioExceptionType.cancel)) {
        throw const DownloadCancelledException();
      }
      rethrow;
    } finally {
      if (identical(_activeTransfers[transferKey], cancelToken)) {
        _activeTransfers.remove(transferKey);
      }
    }
  }

  /// Downloads temporary audio for a lyric-video render without adding it to
  /// the offline library or the user's visible downloads folder.
  Future<String> downloadTemporaryAudio(
    SongModel song,
    String streamUrl, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // Cache can be reclaimed by Android while a long export is still using
    // the source. Keep this private, export-only input in app support storage
    // and remove it through deleteTemporaryAudio when the job finishes.
    final support = await getApplicationSupportDirectory();
    if (isCancelled?.call() == true) {
      throw const DownloadCancelledException();
    }
    final directory = Directory(p.join(support.path, 'muzic_video_audio'));
    await directory.create(recursive: true);
    if (isCancelled?.call() == true) {
      throw const DownloadCancelledException();
    }

    final extension = _audioExtension(streamUrl);
    final unique = DateTime.now().microsecondsSinceEpoch;
    final outputPath = p.join(
      directory.path,
      '${trackFileBase(song.title)}-$unique$extension',
    );
    final partialPath = '$outputPath.part';
    final audioFile = File(partialPath);
    final transferKey = 'video:${song.id}';
    final cancelToken = CancelToken();
    _activeTransfers[transferKey] = cancelToken;
    try {
      if (isCancelled?.call() == true) {
        throw const DownloadCancelledException();
      }
      onProgress?.call(0);
      await _dio.download(
        streamUrl,
        partialPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0).toDouble());
          }
        },
        deleteOnError: true,
        options: Options(
          headers: const <String, String>{'Accept': '*/*'},
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (cancelToken.isCancelled) throw const DownloadCancelledException();
      if (!await audioFile.exists() || await audioFile.length() == 0) {
        throw const FileSystemException('The downloaded audio file is empty.');
      }
      return (await audioFile.rename(outputPath)).path;
    } catch (error) {
      if (await audioFile.exists()) await audioFile.delete();
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      if (cancelToken.isCancelled ||
          (error is DioException && error.type == DioExceptionType.cancel)) {
        throw const DownloadCancelledException();
      }
      rethrow;
    } finally {
      if (identical(_activeTransfers[transferKey], cancelToken)) {
        _activeTransfers.remove(transferKey);
      }
    }
  }

  Future<void> removeDownload(SongModel song) async {
    final saved = _library.downloadedSong(song.id);
    for (final path in <String?>[saved?.localPath, saved?.localArtworkPath]) {
      if (path == null || path.isEmpty) continue;
      if (path.startsWith('content://')) {
        await _localFiles.deleteSharedFile(path);
        continue;
      }
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _library.removeDownload(song.id);
  }

  String _audioExtension(String url) {
    final uri = Uri.tryParse(url);
    final pathExtension = uri == null ? '' : p.extension(uri.path).toLowerCase();
    if (pathExtension == '.webm' || pathExtension == '.opus') return pathExtension;
    if (pathExtension == '.ogg' || pathExtension == '.mp3') return pathExtension;
    if (pathExtension == '.m4a') return '.m4a';
    if (pathExtension == '.mp4') return '.m4a';
    final mime = uri?.queryParameters['mime']?.toLowerCase() ?? '';
    if (mime.contains('webm')) return '.webm';
    if (mime.contains('ogg')) return '.ogg';
    if (mime.contains('mpeg')) return '.mp3';
    return '.m4a';
  }

  String _mimeTypeForExtension(String extension) {
    return switch (extension) {
      '.mp3' => 'audio/mpeg',
      '.m4a' || '.mp4' => 'audio/mp4',
      '.ogg' => 'audio/ogg',
      '.opus' => 'audio/opus',
      '.webm' => 'audio/webm',
      _ => 'audio/*',
    };
  }

  String _imageExtension(String url) {
    final extension = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    if (const <String>{'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)) {
      return extension;
    }
    return '.jpg';
  }
}
