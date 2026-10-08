class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

class LyricsModel {
  const LyricsModel({
    this.syncedLines = const <LyricLine>[],
    this.plainLyrics = '',
  });

  final List<LyricLine> syncedLines;
  final String plainLyrics;

  bool get isEmpty => syncedLines.isEmpty && plainLyrics.trim().isEmpty;
}
