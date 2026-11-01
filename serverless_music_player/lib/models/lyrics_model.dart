class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

/// A single lyrics document in one language/script variant.
class LyricsModel {
  const LyricsModel({
    this.syncedLines = const <LyricLine>[],
    this.plainLyrics = '',
    this.source = '',
    this.language = '',
    this.languageLabel = '',
    this.script = '',
    this.isRomanized = false,
  });

  final List<LyricLine> syncedLines;
  final String plainLyrics;

  /// Provider that produced this variant ('lrclib', 'jiosaavn', 'derived').
  final String source;

  /// Normalized language name such as 'hindi' or 'english'.
  final String language;

  /// Human label shown in the language picker, e.g. 'Hindi' or 'Romanized'.
  final String languageLabel;

  /// Detected script of the text: 'devanagari', 'latin', 'telugu', ...
  final String script;

  /// True when the text is Latin-script transliteration of an Indic language.
  final bool isRomanized;

  bool get isEmpty => syncedLines.isEmpty && plainLyrics.trim().isEmpty;

  bool get hasSynced => syncedLines.isNotEmpty;

  /// Label for UI lists: e.g. "Hindi · Synced (Lyrics source)".
  String get displayLabel {
    final parts = <String>[
      if (languageLabel.isNotEmpty) languageLabel,
      if (hasSynced)
        'Synced'
      else if (!isEmpty)
        'Plain',
      if (source.isNotEmpty) _sourceLabel(source),
    ];
    return parts.join(' · ');
  }

  static String _sourceLabel(String source) {
    if (source.startsWith('lrclib')) return 'Lyrics source';
    if (source.startsWith('jiosaavn')) return 'Source A';
    return 'Derived';
  }

  LyricsModel copyWith({
    List<LyricLine>? syncedLines,
    String? plainLyrics,
    String? source,
    String? language,
    String? languageLabel,
    String? script,
    bool? isRomanized,
  }) {
    return LyricsModel(
      syncedLines: syncedLines ?? this.syncedLines,
      plainLyrics: plainLyrics ?? this.plainLyrics,
      source: source ?? this.source,
      language: language ?? this.language,
      languageLabel: languageLabel ?? this.languageLabel,
      script: script ?? this.script,
      isRomanized: isRomanized ?? this.isRomanized,
    );
  }
}

/// All lyrics variants discovered for one track.
class LyricsBundle {
  const LyricsBundle({required this.songId, this.variants = const <LyricsModel>[]});

  final String songId;
  final List<LyricsModel> variants;

  bool get isEmpty => variants.where((variant) => !variant.isEmpty).isEmpty;
}
