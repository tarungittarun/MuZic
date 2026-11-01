/// Script detection, Indic-to-Latin transliteration and lyrics variant
/// selection. Pure Dart so the logic is fully unit-testable.
library;

import '../models/lyrics_model.dart';
import '../models/song_model.dart';

/// Language names (matching JioSaavn's `language` values) treated as Indic
/// languages whose lyrics may appear in either native script or romanized
/// Latin form.
const Set<String> kIndicLanguages = <String>{
  'hindi',
  'marathi',
  'nepali',
  'sanskrit',
  'bengali',
  'punjabi',
  'gujarati',
  'tamil',
  'telugu',
  'kannada',
  'malayalam',
  'urdu',
  'odia',
  'assamese',
};

/// Preference codes available in settings and the now-playing picker.
const List<String> kLyricsLanguageOptions = <String>[
  'auto',
  'original',
  'romanized',
  'english',
  'hindi',
  'telugu',
  'tamil',
  'kannada',
  'malayalam',
  'bengali',
  'punjabi',
  'gujarati',
  'marathi',
  'urdu',
];

String lyricsLanguageLabel(String code) => switch (code) {
      'auto' => 'Auto (recommended)',
      'original' => 'Original language',
      'romanized' => 'Romanized (Latin letters)',
      'english' => 'English',
      'hindi' => 'Hindi',
      'telugu' => 'Telugu',
      'tamil' => 'Tamil',
      'kannada' => 'Kannada',
      'malayalam' => 'Malayalam',
      'bengali' => 'Bengali',
      'punjabi' => 'Punjabi',
      'gujarati' => 'Gujarati',
      'marathi' => 'Marathi',
      'urdu' => 'Urdu',
      'odia' => 'Odia',
      _ => code.isEmpty ? 'Auto (recommended)' : code,
    };

String normalizeLanguageName(String raw) => raw.trim().toLowerCase();

String capitalizeLanguage(String language) {
  if (language.isEmpty) return language;
  return language[0].toUpperCase() + language.substring(1);
}

/// Detects the dominant script of [text].
///
/// Returns one of 'latin', 'devanagari', 'bengali', 'gurmukhi', 'gujarati',
/// 'tamil', 'telugu', 'kannada', 'malayalam', 'arabic', 'other', 'empty'.
String detectScript(String text) {
  final counts = <String, int>{};
  for (final rune in text.runes) {
    final script = _scriptForRune(rune);
    if (script == null) continue;
    counts[script] = (counts[script] ?? 0) + 1;
  }
  if (counts.isEmpty) return 'empty';
  String best = 'other';
  var bestCount = 0;
  counts.forEach((script, count) {
    if (count > bestCount) {
      best = script;
      bestCount = count;
    }
  });
  return best;
}

String? _scriptForRune(int rune) {
  if (rune <= 0x7F) {
    final isLetter = (rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122);
    return isLetter ? 'latin' : null;
  }
  // Latin extended accents.
  if (rune >= 0x00C0 && rune <= 0x024F) return 'latin';
  if (rune >= 0x0900 && rune <= 0x097F) return 'devanagari';
  if (rune >= 0x0980 && rune <= 0x09FF) return 'bengali';
  if (rune >= 0x0A00 && rune <= 0x0A7F) return 'gurmukhi';
  if (rune >= 0x0A80 && rune <= 0x0AFF) return 'gujarati';
  if (rune >= 0x0B00 && rune <= 0x0B7F) return 'oriya';
  if (rune >= 0x0B80 && rune <= 0x0BFF) return 'tamil';
  if (rune >= 0x0C00 && rune <= 0x0C7F) return 'telugu';
  if (rune >= 0x0C80 && rune <= 0x0CFF) return 'kannada';
  if (rune >= 0x0D00 && rune <= 0x0D7F) return 'malayalam';
  if (rune >= 0x0600 && rune <= 0x06FF) return 'arabic';
  return null;
}

/// Maps a detected script to a canonical language name when unambiguous.
String? languageForScript(String script) => switch (script) {
      'devanagari' => 'hindi',
      'bengali' => 'bengali',
      'gurmukhi' => 'punjabi',
      'gujarati' => 'gujarati',
      'oriya' => 'odia',
      'tamil' => 'tamil',
      'telugu' => 'telugu',
      'kannada' => 'kannada',
      'malayalam' => 'malayalam',
      'arabic' => 'urdu',
      _ => null,
    };

/// Adds source/language/script metadata to a raw lyrics document so it can
/// participate in language selection.
LyricsModel annotateLyrics(
  LyricsModel lyrics,
  SongModel song, {
  required String source,
}) {
  if (lyrics.isEmpty) {
    return lyrics.copyWith(source: source);
  }
  final body = lyrics.hasSynced
      ? lyrics.syncedLines.map((line) => line.text).join('\n')
      : lyrics.plainLyrics;
  final script = detectScript(body);
  final songLanguage = normalizeLanguageName(song.language);
  final String language;
  final bool romanized;
  final String label;
  if (script == 'latin' || script == 'other') {
    if (kIndicLanguages.contains(songLanguage)) {
      romanized = true;
      language = songLanguage;
      label = 'Romanized ${capitalizeLanguage(songLanguage)}';
    } else {
      romanized = false;
      language = songLanguage.isNotEmpty ? songLanguage : 'english';
      label = language == 'english'
          ? 'English'
          : capitalizeLanguage(language);
    }
  } else {
    romanized = false;
    language = languageForScript(script) ??
        (songLanguage.isNotEmpty ? songLanguage : 'unknown');
    label = capitalizeLanguage(language);
  }
  return lyrics.copyWith(
    source: source,
    language: language,
    languageLabel: label,
    script: script,
    isRomanized: romanized,
  );
}

/// Converts an original-script variant to Latin letters.
LyricsModel romanizeLyrics(LyricsModel lyrics) {
  if (lyrics.isRomanized || lyrics.isEmpty) return lyrics;
  final lines = lyrics.syncedLines
      .map((line) => LyricLine(
            time: line.time,
            text: romanizeIndic(line.text),
          ))
      .toList(growable: false);
  final plain =
      lyrics.plainLyrics.isEmpty ? '' : romanizeIndic(lyrics.plainLyrics);
  final label = lyrics.languageLabel.startsWith('Romanized')
      ? lyrics.languageLabel
      : 'Romanized ${capitalizeLanguage(lyrics.language)}';
  return lyrics.copyWith(
    syncedLines: lines,
    plainLyrics: plain,
    script: 'latin',
    isRomanized: true,
    source: lyrics.source.isEmpty ? 'derived' : '${lyrics.source}+derived',
    languageLabel: label,
  );
}

/// Picks the best variant for a preference code.
///
/// Preference codes: 'auto', 'original', 'romanized' or a language name such
/// as 'hindi'. [override] (a per-song choice) wins over [preference].
/// May return a derived romanized variant. Returns null when nothing matches.
LyricsModel? selectLyricsVariant({
  required List<LyricsModel> variants,
  required SongModel song,
  required String preference,
  String? override,
}) {
  final wanted =
      (override != null && override.isNotEmpty) ? override : preference;
  final usable =
      variants.where((variant) => !variant.isEmpty).toList(growable: false);
  if (usable.isEmpty) return null;
  final songLanguage = normalizeLanguageName(song.language);
  final targetLanguage =
      songLanguage.isNotEmpty ? songLanguage : 'english';

  if (wanted == 'romanized') {
    final romanized =
        usable.where((variant) => variant.isRomanized).toList(growable: false);
    if (romanized.isNotEmpty) return _preferSynced(romanized);
    final base = _pickOriginal(usable, targetLanguage) ?? usable.first;
    return romanizeLyrics(base);
  }
  if (wanted == 'original') {
    return _pickOriginal(usable, targetLanguage) ?? _preferSynced(usable);
  }
  if (wanted == 'auto') {
    final original = _pickOriginal(usable, targetLanguage);
    if (original != null) return original;
    final sameLanguage = usable
        .where((variant) => variant.language == targetLanguage)
        .toList(growable: false);
    if (sameLanguage.isNotEmpty) return _preferSynced(sameLanguage);
    return _preferSynced(usable);
  }
  // A specific language name such as 'hindi' or 'english'.
  final matches = usable
      .where((variant) => variant.language == wanted)
      .toList(growable: false);
  if (matches.isEmpty) return null;
  final original =
      matches.where((variant) => !variant.isRomanized).toList(growable: false);
  return original.isNotEmpty ? _preferSynced(original) : _preferSynced(matches);
}

LyricsModel? _pickOriginal(
  List<LyricsModel> usable,
  String targetLanguage,
) {
  final originals = usable
      .where((variant) => !variant.isRomanized)
      .toList(growable: false);
  if (originals.isEmpty) return null;
  final sameLanguage = originals
      .where((variant) => variant.language == targetLanguage)
      .toList(growable: false);
  return _preferSynced(sameLanguage.isNotEmpty ? sameLanguage : originals);
}

LyricsModel _preferSynced(List<LyricsModel> list) {
  for (final variant in list) {
    if (variant.hasSynced) return variant;
  }
  return list.first;
}

/// Transliterates Indic scripts (Devanagari, Telugu, Tamil, ...) to readable
/// Latin letters. Unknown characters pass through unchanged.
String romanizeIndic(String text) {
  final buffer = StringBuffer();
  var pendingInherent = false;

  void flushInherent() {
    if (pendingInherent) {
      buffer.write('a');
      pendingInherent = false;
    }
  }

  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final consonant = _consonants[char];
    if (consonant != null) {
      flushInherent();
      buffer.write(consonant);
      pendingInherent = true;
      continue;
    }
    final vowelSign = _vowelSigns[char];
    if (vowelSign != null) {
      // A vowel sign replaces the inherent 'a' of the preceding consonant.
      buffer.write(vowelSign);
      pendingInherent = false;
      continue;
    }
    final independent = _independentVowels[char];
    if (independent != null) {
      flushInherent();
      buffer.write(independent);
      continue;
    }
    if (_viramas.contains(char)) {
      pendingInherent = false;
      continue;
    }
    final sign = _signs[char];
    if (sign != null) {
      flushInherent();
      buffer.write(sign);
      continue;
    }
    if (_ignore.contains(char)) {
      continue;
    }
    final digit = _digits[char];
    if (digit != null) {
      flushInherent();
      buffer.write(digit);
      continue;
    }
    flushInherent();
    buffer.write(char);
  }
  flushInherent();
  return buffer.toString();
}

final Map<String, String> _consonants = <String, String>{
  // Devanagari.
  'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
  'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
  'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
  'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
  'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
  'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh', 'ष': 'sh',
  'स': 's', 'ह': 'h', 'ळ': 'l', 'ऴ': 'l', 'क्ष': 'ksh', 'ज्ञ': 'jny',
  // Bengali.
  'ক': 'k', 'খ': 'kh', 'গ': 'g', 'ঘ': 'gh', 'ঙ': 'ng',
  'চ': 'ch', 'ছ': 'chh', 'জ': 'j', 'ঝ': 'jh', 'ঞ': 'ny',
  'ট': 't', 'ঠ': 'th', 'ড': 'd', 'ঢ': 'dh', 'ণ': 'n',
  'ত': 't', 'থ': 'th', 'দ': 'd', 'ধ': 'dh', 'ন': 'n',
  'প': 'p', 'ফ': 'ph', 'ব': 'b', 'ভ': 'bh', 'ম': 'm',
  'য': 'y', 'র': 'r', 'ল': 'l', 'শ': 'sh', 'ষ': 'sh', 'স': 's', 'হ': 'h',
  // Gurmukhi.
  'ਕ': 'k', 'ਖ': 'kh', 'ਗ': 'g', 'ਘ': 'gh', 'ਙ': 'ng',
  'ਚ': 'ch', 'ਛ': 'chh', 'ਜ': 'j', 'ਝ': 'jh', 'ਞ': 'ny',
  'ਟ': 't', 'ਠ': 'th', 'ਡ': 'd', 'ਢ': 'dh', 'ਣ': 'n',
  'ਤ': 't', 'ਥ': 'th', 'ਦ': 'd', 'ਧ': 'dh', 'ਨ': 'n',
  'ਪ': 'p', 'ਫ': 'ph', 'ਬ': 'b', 'ਭ': 'bh', 'ਮ': 'm',
  'ਯ': 'y', 'ਰ': 'r', 'ਲ': 'l', 'ਵ': 'v', 'ਸ': 's', 'ਹ': 'h',
  // Gujarati.
  'ક': 'k', 'ખ': 'kh', 'ગ': 'g', 'ઘ': 'gh', 'ઙ': 'ng',
  'ચ': 'ch', 'છ': 'chh', 'જ': 'j', 'ઝ': 'jh', 'ઞ': 'ny',
  'ટ': 't', 'ઠ': 'th', 'ડ': 'd', 'ઢ': 'dh', 'ણ': 'n',
  'ત': 't', 'થ': 'th', 'દ': 'd', 'ધ': 'dh', 'ન': 'n',
  'પ': 'p', 'ફ': 'ph', 'બ': 'b', 'ભ': 'bh', 'મ': 'm',
  'ય': 'y', 'ર': 'r', 'લ': 'l', 'વ': 'v', 'શ': 'sh', 'ષ': 'sh',
  'સ': 's', 'હ': 'h',
  // Tamil.
  'க': 'k', 'ங': 'ng', 'ச': 'ch', 'ஞ': 'ny', 'ட': 't', 'ண': 'n',
  'த': 't', 'ந': 'n', 'ப': 'p', 'ம': 'm', 'ய': 'y', 'ர': 'r',
  'ல': 'l', 'வ': 'v', 'ழ': 'zh', 'ள': 'l', 'ற': 'r', 'ன': 'n',
  'ஜ': 'j', 'ஷ': 'sh', 'ஸ': 's', 'ஹ': 'h',
  // Telugu.
  'క': 'k', 'ఖ': 'kh', 'గ': 'g', 'ఘ': 'gh', 'ఙ': 'ng',
  'చ': 'ch', 'ఛ': 'chh', 'జ': 'j', 'ఝ': 'jh', 'ఞ': 'ny',
  'ట': 't', 'ఠ': 'th', 'డ': 'd', 'ఢ': 'dh', 'ణ': 'n',
  'త': 't', 'థ': 'th', 'ద': 'd', 'ధ': 'dh', 'న': 'n',
  'ప': 'p', 'ఫ': 'ph', 'బ': 'b', 'భ': 'bh', 'మ': 'm',
  'య': 'y', 'ర': 'r', 'ల': 'l', 'వ': 'v', 'శ': 'sh', 'ష': 'sh',
  'స': 's', 'హ': 'h', 'ళ': 'l', 'ఴ': 'zh',
  // Kannada.
  'ಕ': 'k', 'ಖ': 'kh', 'ಗ': 'g', 'ಘ': 'gh', 'ಙ': 'ng',
  'ಚ': 'ch', 'ಛ': 'chh', 'ಜ': 'j', 'ಝ': 'jh', 'ಞ': 'ny',
  'ಟ': 't', 'ಠ': 'th', 'ಡ': 'd', 'ಢ': 'dh', 'ಣ': 'n',
  'ತ': 't', 'ಥ': 'th', 'ದ': 'd', 'ಧ': 'dh', 'ನ': 'n',
  'ಪ': 'p', 'ಫ': 'ph', 'ಬ': 'b', 'ಭ': 'bh', 'ಮ': 'm',
  'ಯ': 'y', 'ರ': 'r', 'ಲ': 'l', 'ವ': 'v', 'ಶ': 'sh', 'ಷ': 'sh',
  'ಸ': 's', 'ಹ': 'h', 'ಳ': 'l',
  // Malayalam.
  'ക': 'k', 'ഖ': 'kh', 'ഗ': 'g', 'ഘ': 'gh', 'ങ': 'ng',
  'ച': 'ch', 'ഛ': 'chh', 'ജ': 'j', 'ഝ': 'jh', 'ഞ': 'ny',
  'ട': 't', 'ഠ': 'th', 'ഡ': 'd', 'ഢ': 'dh', 'ണ': 'n',
  'ത': 't', 'ഥ': 'th', 'ദ': 'd', 'ധ': 'dh', 'ന': 'n',
  'പ': 'p', 'ഫ': 'ph', 'ബ': 'b', 'ഭ': 'bh', 'മ': 'm',
  'യ': 'y', 'ര': 'r', 'ല': 'l', 'വ': 'v', 'ശ': 'sh', 'ഷ': 'sh',
  'സ': 's', 'ഹ': 'h', 'ള': 'l', 'ഴ': 'zh',
};

final Map<String, String> _vowelSigns = <String, String>{
  // Devanagari.
  'ा': 'aa', 'ि': 'i', 'ी': 'ii', 'ु': 'u', 'ू': 'uu', 'ृ': 'ri',
  'ॄ': 'rii', 'ॅ': 'e', 'े': 'e', 'ै': 'ai', 'ॉ': 'o', 'ो': 'o',
  'ौ': 'au',
  // Bengali.
  'া': 'aa', 'ি': 'i', 'ী': 'ii', 'ু': 'u', 'ূ': 'uu', 'ৃ': 'ri',
  'ে': 'e', 'ৈ': 'ai', 'ো': 'o', 'ৌ': 'au',
  // Gurmukhi.
  'ਾ': 'aa', 'ਿ': 'i', 'ੀ': 'ii', 'ੁ': 'u', 'ੂ': 'uu', 'ੇ': 'e',
  'ੈ': 'ai', 'ੋ': 'o', 'ੌ': 'au',
  // Gujarati.
  'ા': 'aa', 'િ': 'i', 'ી': 'ii', 'ુ': 'u', 'ૂ': 'uu', 'ૃ': 'ri',
  'ે': 'e', 'ૈ': 'ai', 'ો': 'o', 'ૌ': 'au',
  // Tamil.
  'ா': 'aa', 'ி': 'i', 'ீ': 'ii', 'ு': 'u', 'ூ': 'uu', 'ெ': 'e',
  'ே': 'ee', 'ை': 'ai', 'ொ': 'o', 'ோ': 'oo', 'ௌ': 'au',
  // Telugu.
  'ా': 'aa', 'ి': 'i', 'ీ': 'ii', 'ు': 'u', 'ూ': 'uu', 'ృ': 'ri',
  'ె': 'e', 'ే': 'ee', 'ై': 'ai', 'ొ': 'o', 'ో': 'oo', 'ౌ': 'au',
  // Kannada.
  'ಾ': 'aa', 'ಿ': 'i', 'ೀ': 'ii', 'ು': 'u', 'ೂ': 'uu', 'ೃ': 'ri',
  'ೆ': 'e', 'ೇ': 'ee', 'ೈ': 'ai', 'ೊ': 'o', 'ೋ': 'oo', 'ೌ': 'au',
  // Malayalam.
  'ാ': 'aa', 'ി': 'i', 'ീ': 'ii', 'ു': 'u', 'ൂ': 'uu', 'ൃ': 'ri',
  'െ': 'e', 'േ': 'ee', 'ൈ': 'ai', 'ൊ': 'o', 'ോ': 'oo', 'ൌ': 'au',
};

final Map<String, String> _independentVowels = <String, String>{
  // Devanagari.
  'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ii', 'उ': 'u', 'ऊ': 'uu',
  'ऋ': 'ri', 'ॠ': 'rii', 'ऌ': 'li', 'ऍ': 'e', 'ए': 'e', 'ऐ': 'ai',
  'ऑ': 'o', 'ओ': 'o', 'औ': 'au',
  // Bengali.
  'অ': 'a', 'আ': 'aa', 'ই': 'i', 'ঈ': 'ii', 'উ': 'u', 'ঊ': 'uu',
  'ঋ': 'ri', 'এ': 'e', 'ঐ': 'ai', 'ও': 'o', 'ঔ': 'au',
  // Gurmukhi.
  'ਅ': 'a', 'ਆ': 'aa', 'ਇ': 'i', 'ਈ': 'ii', 'ਉ': 'u', 'ਊ': 'uu',
  'ਏ': 'e', 'ਐ': 'ai', 'ਓ': 'o', 'ਔ': 'au',
  // Gujarati.
  'અ': 'a', 'આ': 'aa', 'ઇ': 'i', 'ઈ': 'ii', 'ઉ': 'u', 'ઊ': 'uu',
  'ઋ': 'ri', 'એ': 'e', 'ઐ': 'ai', 'ઓ': 'o', 'ઔ': 'au',
  // Tamil.
  'அ': 'a', 'ஆ': 'aa', 'இ': 'i', 'ஈ': 'ii', 'உ': 'u', 'ஊ': 'uu',
  'எ': 'e', 'ஏ': 'ee', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'oo', 'ஔ': 'au',
  // Telugu.
  'అ': 'a', 'ఆ': 'aa', 'ఇ': 'i', 'ఈ': 'ii', 'ఉ': 'u', 'ఊ': 'uu',
  'ఋ': 'ri', 'ౠ': 'rii', 'ఌ': 'li', 'ఎ': 'e', 'ఏ': 'ee', 'ఐ': 'ai',
  'ఒ': 'o', 'ఓ': 'oo', 'ఔ': 'au',
  // Kannada.
  'ಅ': 'a', 'ಆ': 'aa', 'ಇ': 'i', 'ಈ': 'ii', 'ಉ': 'u', 'ಊ': 'uu',
  'ಋ': 'ri', 'ೠ': 'rii', 'ಌ': 'li', 'ಎ': 'e', 'ಏ': 'ee', 'ಐ': 'ai',
  'ಒ': 'o', 'ಓ': 'oo', 'ಔ': 'au',
  // Malayalam.
  'അ': 'a', 'ആ': 'aa', 'ഇ': 'i', 'ഈ': 'ii', 'ഉ': 'u', 'ഊ': 'uu',
  'ഋ': 'ri', 'ൠ': 'rii', 'ഌ': 'li', 'എ': 'e', 'ഏ': 'ee', 'ഐ': 'ai',
  'ഒ': 'o', 'ഓ': 'oo', 'ഔ': 'au',
};

final Set<String> _viramas = <String>{
  '्', // Devanagari
  '্', // Bengali
  '੍', // Gurmukhi
  '્', // Gujarati
  '்', // Tamil
  '్', // Telugu
  '್', // Kannada
  '്', // Malayalam
};

final Map<String, String> _signs = <String, String>{
  'ं': 'n', // Devanagari anusvara
  'ँ': 'n', // Devanagari chandrabindu
  'ः': 'h', // Devanagari visarga
  'ং': 'n', 'ঁ': 'n', 'ঃ': 'h', // Bengali
  'ਂ': 'n', 'ਁ': 'n', 'ਃ': 'h', // Gurmukhi
  'ં': 'n', 'ઁ': 'n', 'ઃ': 'h', // Gujarati
  'ஂ': 'n', 'ஃ': 'h', // Tamil
  'ం': 'n', 'ః': 'h', // Telugu
  'ಂ': 'n', 'ಃ': 'h', // Kannada
  'ം': 'n', 'ഃ': 'h', // Malayalam
  'ॐ': 'om',
  '।': '.',
  '॥': '..',
};

final Set<String> _ignore = <String>{
  '़', // Devanagari nukta
  'ऽ', // avagraha
  '‍', // zero width joiner
  '‌', // zero width non-joiner
};

final Map<String, String> _digits = <String, String>{
  '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
  '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
};
