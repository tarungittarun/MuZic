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

/// Bridges to the platform document picker so users can import their own
/// FLAC/WAV/AIFF/MP3 files into the local library.
class LocalFilesService {
  LocalFilesService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('music_player/local_files');

  final MethodChannel _channel;

  /// Opens the system picker and copies the chosen files into app storage.
  /// Returns an empty list when the user cancels.
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
}
