import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song_model.dart';
import 'library_service.dart';

class DownloadService {
  DownloadService({required LibraryService library, Dio? dio})
      : _library = library,
        _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 12),
          sendTimeout: const Duration(seconds: 20),
          followRedirects: true,
          maxRedirects: 5,
        ));

  final LibraryService _library;
  final Dio _dio;

  Future<String?> localPathFor(String songId) async {
    final song = _library.downloadedSong(songId);
    final path = song?.localPath;
    if (path == null || path.isEmpty) return null;
    return await File(path).exists() ? path : null;
  }

  Future<SongModel> downloadSong(
    SongModel song,
    String streamUrl, {
    void Function(double progress)? onProgress,
  }) async {
    final existing = _library.downloadedSong(song.id);
    if (existing?.localPath != null &&
        await File(existing!.localPath!).exists()) {
      return existing;
    }

    final root = await getApplicationDocumentsDirectory();
    final musicDirectory = Directory(p.join(root.path, 'music'));
    final artworkDirectory = Directory(p.join(musicDirectory.path, 'artwork'));
    await musicDirectory.create(recursive: true);
    await artworkDirectory.create(recursive: true);

    final safeId = song.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final extension = _audioExtension(streamUrl);
    final outputPath = p.join(musicDirectory.path, '$safeId$extension');
    final partialPath = '$outputPath.part';
    final audioFile = File(partialPath);
    if (await audioFile.exists()) await audioFile.delete();
    final previousOutput = File(outputPath);
    if (await previousOutput.exists()) await previousOutput.delete();

    try {
      await _dio.download(
        streamUrl,
        partialPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0).toDouble());
          }
        },
        deleteOnError: true,
        options: Options(
          headers: const <String, String>{'Accept': '*/*'},
          responseType: ResponseType.stream,
          validateStatus: (status) => status != null && status >= 200 && status < 300,
        ),
      );
      if (!await audioFile.exists() || await audioFile.length() == 0) {
        throw const FileSystemException('The downloaded audio file is empty.');
      }
      final savedAudio = await audioFile.rename(outputPath);
      String? artworkPath;
      if (song.artworkUrl.startsWith('https://') ||
          song.artworkUrl.startsWith('http://')) {
        final imageExtension = _imageExtension(song.artworkUrl);
        final imageFile = File(
          p.join(artworkDirectory.path, '$safeId$imageExtension'),
        );
        try {
          await _dio.download(
            song.artworkUrl,
            imageFile.path,
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
        } on DioException {
          artworkPath = null;
        } on FileSystemException {
          artworkPath = null;
        }
      }

      final savedSong = song.copyWith(
        localPath: savedAudio.path,
        localArtworkPath: artworkPath,
      );
      await _library.saveDownload(savedSong);
      onProgress?.call(1.0);
      return savedSong;
    } catch (_) {
      if (await audioFile.exists()) await audioFile.delete();
      rethrow;
    }
  }

  Future<void> removeDownload(SongModel song) async {
    final saved = _library.downloadedSong(song.id);
    for (final path in <String?>[saved?.localPath, saved?.localArtworkPath]) {
      if (path == null || path.isEmpty) continue;
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

  String _imageExtension(String url) {
    final extension = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    if (const <String>{'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)) {
      return extension;
    }
    return '.jpg';
  }
}
