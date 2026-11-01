import 'package:flutter/services.dart';

import 'app_log.dart';

/// A file copied into app storage by the Android document picker.
class ImportedLocalFile {
  const ImportedLocalFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  final String name;
  final String path;
  final int sizeBytes;

  String get title {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return base.replaceAll(RegExp(r'[_]+'), ' ').trim();
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  bool get isLosslessFormat {
    return const <String>{'flac', 'wav', 'aiff', 'aif'}.contains(extension);
  }
}

/// A device folder the user picked for new downloads (Android tree URI).
class PickedDownloadsFolder {
  const PickedDownloadsFolder({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// Bridges to the platform document picker so users can import their own
/// FLAC/WAV/AIFF/MP3 files into the local library.
class LocalFilesService {
  LocalFilesService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('music_player/local_files');

  final MethodChannel _channel;

  /// Opens the system picker and copies the chosen files into app storage.
  /// Returns an empty list when the user cancels.
  /// Shares a downloaded song's file exactly as saved (no re-encode or
  /// quality change) through Android's share sheet. Returns false when the
  /// file is missing or the share could not be started.
  Future<bool> shareFile({
    required String path,
    required String fileName,
  }) async {
    if (path.isEmpty) return false;
    try {
      final shared = await _channel.invokeMethod<bool>(
        'shareFile',
        <String, String>{'path': path, 'fileName': fileName},
      );
      return shared ?? false;
    } on MissingPluginException {
      logWarn('local', 'file sharing is unavailable on this platform');
      return false;
    } on PlatformException catch (error) {
      logWarn('local', 'file share failed', <String, Object?>{
        'error': '$error',
      });
      return false;
    }
  }

  Future<List<ImportedLocalFile>> pickAudioFiles() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pickAudioFiles');
      if (result == null) return const <ImportedLocalFile>[];
      final files = <ImportedLocalFile>[];
      for (final entry in result) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final path = map['path']?.toString() ?? '';
        if (path.isEmpty) continue;
        files.add(
          ImportedLocalFile(
            name: map['name']?.toString() ?? 'track',
            path: path,
            sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      logInfo('local', 'imported files', <String, Object?>{
        'count': files.length,
        'lossless': files.where((file) => file.isLosslessFormat).length,
      });
      return files;
    } on MissingPluginException {
      logWarn('local', 'file picker is unavailable on this platform');
      return const <ImportedLocalFile>[];
    } on PlatformException catch (error) {
      logWarn('local', 'file import failed', <String, Object?>{'error': '$error'});
      return const <ImportedLocalFile>[];
    }
  }

  /// Opens Android's folder picker for the custom downloads location.
  /// Returns null when the user cancels or picking is unavailable.
  Future<PickedDownloadsFolder?> pickDownloadsFolder() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pickDownloadsFolder',
      );
      if (result == null) return null;
      final uri = result['uri']?.toString() ?? '';
      if (uri.isEmpty) return null;
      return PickedDownloadsFolder(
        uri: uri,
        name: result['name']?.toString() ?? 'Selected folder',
      );
    } on MissingPluginException {
      logWarn('local', 'folder picker is unavailable on this platform');
      return null;
    } on PlatformException catch (error) {
      logWarn('local', 'folder pick failed', <String, Object?>{
        'error': '$error',
      });
      return null;
    }
  }

  /// Copies [sourcePath] into the picked downloads folder without changing
  /// its bytes, returning the new file's content URI (or null on failure).
  Future<String?> copyFileToDownloadsFolder({
    required String folderUri,
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      final copied = await _channel.invokeMethod<String>(
        'copyToDownloadsFolder',
        <String, String>{
          'folderUri': folderUri,
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      return copied == null || copied.isEmpty ? null : copied;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      logWarn('local', 'copy to downloads folder failed', <String, Object?>{
        'error': '$error',
      });
      return null;
    }
  }

  /// Checks that a content:// download is still readable before reusing it.
  Future<bool> contentFileExists(String path) async {
    if (!path.startsWith('content://')) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'contentFileExists',
            <String, String>{'path': path},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      logWarn('local', 'content file check failed', <String, Object?>{
        'error': '$error',
      });
      return false;
    }
  }

  /// Deletes a file addressed by a content:// URI (custom-folder download).
  Future<void> deleteSharedFile(String path) async {
    if (!path.startsWith('content://')) return;
    try {
      await _channel.invokeMethod<bool>(
        'deleteContentFile',
        <String, String>{'path': path},
      );
    } on MissingPluginException {
      // Nothing to clean up on platforms without the bridge.
    } on PlatformException catch (error) {
      logWarn('local', 'content file delete failed', <String, Object?>{
        'error': '$error',
      });
    }
  }
}
