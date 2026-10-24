import '../models/lyrics_model.dart';

/// Supplies approximate caption times for a lyric video when only plain
/// lyrics are available. The original lyrics model remains untouched, so the
/// player never claims that estimated timestamps are live-synced.
LyricsModel? estimateLyricsTimingForVideo(
  LyricsModel? lyrics, {
  Duration? duration,
}) {
  if (lyrics == null || lyrics.isEmpty || lyrics.hasSynced) return lyrics;

  final textLines = lyrics.plainLyrics
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(240)
      .toList(growable: false);
  if (textLines.isEmpty) return null;

  final requestedDurationMs = duration?.inMilliseconds ?? 0;
  final totalDurationMs = requestedDurationMs > 0
      ? requestedDurationMs
      : (textLines.length * 4000).clamp(60000, 600000);
  final finalCaptionMs = (totalDurationMs - 2500).clamp(0, totalDurationMs);
  final intervalMs = textLines.length <= 1
      ? 0.0
      : finalCaptionMs / (textLines.length - 1);
  final estimatedLines = <LyricLine>[
    for (var index = 0; index < textLines.length; index++)
      LyricLine(
        time: Duration(milliseconds: (index * intervalMs).round()),
        text: textLines[index],
      ),
  ];
  return lyrics.copyWith(syncedLines: estimatedLines);
}
