import 'song_model.dart';

/// Describes the audio quality of a track honestly (codec, bitrate, lossy vs
/// lossless) based on what the app actually knows about the stream or file.
class AudioQualityInfo {
  const AudioQualityInfo({
    required this.label,
    required this.detail,
    required this.isLossless,
  });

  /// Short badge text, e.g. 'AAC 320 kbps' or 'FLAC 16/44.1 kHz'.
  final String label;

  /// Extra context, e.g. 'Lossy · Source A' or 'Lossless · live stream'.
  final String detail;

  final bool isLossless;

  @override
  String toString() => '$label ($detail)';
}

/// Best-effort quality description for [song] using its source and resolved
/// stream URL. Safe for any source; never throws.
AudioQualityInfo describeAudio(SongModel song) {
  switch (song.source) {
    case SongSource.radio:
      return const AudioQualityInfo(
        label: 'FLAC 16-bit/44.1 kHz',
        detail: 'Lossless · live stream',
        isLossless: true,
      );
    case SongSource.local:
      return _describeLocal(song);
    case SongSource.jioSaavn:
    case SongSource.youtube:
      return _describeRemote(song);
  }
}

AudioQualityInfo _describeLocal(SongModel song) {
  final path = (song.localPath ?? song.streamUrl ?? '').toLowerCase();
  if (path.endsWith('.flac')) {
    return const AudioQualityInfo(
      label: 'FLAC (local file)',
      detail: 'Lossless · imported',
      isLossless: true,
    );
  }
  if (path.endsWith('.wav')) {
    return const AudioQualityInfo(
      label: 'WAV (local file)',
      detail: 'Uncompressed · imported',
      isLossless: true,
    );
  }
  if (path.endsWith('.aiff') || path.endsWith('.aif')) {
    return const AudioQualityInfo(
      label: 'AIFF (local file)',
      detail: 'Uncompressed · imported',
      isLossless: true,
    );
  }
  if (path.endsWith('.m4a') || path.endsWith('.mp4')) {
    return const AudioQualityInfo(
      label: 'AAC / ALAC (local file)',
      detail: 'Imported',
      isLossless: false,
    );
  }
  if (path.endsWith('.mp3')) {
    return const AudioQualityInfo(
      label: 'MP3 (local file)',
      detail: 'Lossy · imported',
      isLossless: false,
    );
  }
  if (path.endsWith('.ogg') || path.endsWith('.opus')) {
    return const AudioQualityInfo(
      label: 'Ogg / Opus (local file)',
      detail: 'Imported',
      isLossless: false,
    );
  }
  return const AudioQualityInfo(
    label: 'Local file',
    detail: 'Imported',
    isLossless: false,
  );
}

AudioQualityInfo _describeRemote(SongModel song) {
  final url = song.streamUrl ?? '';
  if (url.contains('_320.')) {
    return const AudioQualityInfo(
      label: 'AAC 320 kbps',
      detail: 'Lossy · Source A',
      isLossless: false,
    );
  }
  if (url.contains('_96.')) {
    return const AudioQualityInfo(
      label: 'AAC 96 kbps',
      detail: 'Lossy · Source A',
      isLossless: false,
    );
  }
  final lower = url.toLowerCase();
  final looksWebm = lower.contains('audio%2Fwebm') ||
      lower.contains('audio/webm') ||
      lower.contains('opus') ||
      lower.contains('mime=audio%2Fwebm');
  final looksMp4 = lower.contains('audio%2Fmp4') ||
      lower.contains('audio/mp4') ||
      lower.contains('mp4a');
  if (song.source == SongSource.youtube) {
    if (looksWebm) {
      return const AudioQualityInfo(
        label: 'Opus ~160 kbps',
        detail: 'Lossy · Source B',
        isLossless: false,
      );
    }
    if (looksMp4) {
      return const AudioQualityInfo(
        label: 'AAC ~256 kbps',
        detail: 'Lossy · Source B',
        isLossless: false,
      );
    }
    return const AudioQualityInfo(
      label: 'Opus / AAC',
      detail: 'Lossy · Source B',
      isLossless: false,
    );
  }
  if (url.contains('googlevideo.com')) {
    return const AudioQualityInfo(
      label: 'Opus / AAC',
      detail: 'Lossy · Source B fallback',
      isLossless: false,
    );
  }
  if (url.isNotEmpty) {
    return const AudioQualityInfo(
      label: 'AAC (stream)',
      detail: 'Lossy · Source A',
      isLossless: false,
    );
  }
  return const AudioQualityInfo(
    label: 'Unknown',
    detail: 'Not resolved yet',
    isLossless: false,
  );
}
