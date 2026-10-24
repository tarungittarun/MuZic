import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/lyrics_model.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/services/lyrics_language.dart';

void main() {
  group('detectScript', () {
    test('detects Devanagari, Telugu and Latin text', () {
      expect(detectScript('राम सिया राम'), 'devanagari');
      expect(detectScript('రామ సీత'), 'telugu');
      expect(detectScript('Ram Siya Ram'), 'latin');
      expect(detectScript('   '), 'empty');
    });

    test('picks the dominant script in mixed text', () {
      expect(detectScript('राम (Ram)'), 'devanagari');
    });
  });

  group('romanizeIndic', () {
    test('transliterates Devanagari with vowel signs and virama', () {
      expect(romanizeIndic('राम'), 'raama');
      expect(romanizeIndic('सिया'), 'siyaa');
      expect(romanizeIndic('क्ष'), 'ksha');
      expect(romanizeIndic('मंगल'), 'mangala');
      expect(romanizeIndic('भारत'), 'bhaarata');
    });

    test('keeps punctuation, digits and Latin text untouched', () {
      expect(romanizeIndic('राम, 2024!'), 'raama, 2024!');
      expect(romanizeIndic('hello राम'), 'hello raama');
    });

    test('handles independent vowels and sentence-final consonants', () {
      expect(romanizeIndic('अ'), 'a');
      expect(romanizeIndic('नमस्ते'), 'namaste');
    });
  });

  group('annotateLyrics', () {
    const hindiSong = SongModel(
      id: 'saavn:1',
      sourceId: '1',
      title: 'Ram Siya Ram',
      artist: 'Sachet Tandon',
      source: SongSource.jioSaavn,
      language: 'hindi',
    );
    const englishSong = SongModel(
      id: 'saavn:2',
      sourceId: '2',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      source: SongSource.jioSaavn,
      language: 'english',
    );

    test('marks Latin lyrics of an Indic song as romanized', () {
      final annotated = annotateLyrics(
        const LyricsModel(plainLyrics: 'Kaushlya Dasrath Ke Nandan'),
        hindiSong,
        source: 'jiosaavn',
      );
      expect(annotated.isRomanized, isTrue);
      expect(annotated.language, 'hindi');
      expect(annotated.languageLabel, 'Romanized Hindi');
    });

    test('keeps Devanagari lyrics as original Hindi', () {
      final annotated = annotateLyrics(
        const LyricsModel(plainLyrics: 'कौशल्या दशरथ के नंदन'),
        hindiSong,
        source: 'lrclib',
      );
      expect(annotated.isRomanized, isFalse);
      expect(annotated.language, 'hindi');
      expect(annotated.script, 'devanagari');
      expect(annotated.languageLabel, 'Hindi');
    });

    test('labels Latin lyrics of an English song as English', () {
      final annotated = annotateLyrics(
        const LyricsModel(plainLyrics: 'I have been called'),
        englishSong,
        source: 'lrclib',
      );
      expect(annotated.isRomanized, isFalse);
      expect(annotated.language, 'english');
      expect(annotated.languageLabel, 'English');
    });
  });

  group('selectLyricsVariant', () {
    const song = SongModel(
      id: 'saavn:1',
      sourceId: '1',
      title: 'Ram Siya Ram',
      artist: 'Sachet Tandon',
      source: SongSource.jioSaavn,
      language: 'hindi',
    );
    final original = annotateLyrics(
      const LyricsModel(plainLyrics: 'कौशल्या दशरथ के नंदन'),
      song,
      source: 'lrclib',
    );
    final romanized = annotateLyrics(
      const LyricsModel(plainLyrics: 'Kaushlya Dasrath Ke Nandan'),
      song,
      source: 'jiosaavn',
    );

    test('auto prefers the original-script variant', () {
      final selected = selectLyricsVariant(
        variants: <LyricsModel>[romanized, original],
        song: song,
        preference: 'auto',
      );
      expect(selected, same(original));
    });

    test('auto prefers timed lyrics when the same-language copy is plain', () {
      final plain = annotateLyrics(
        const LyricsModel(plainLyrics: 'कौशल्या दशरथ के नंदन'),
        song,
        source: 'lrclib',
      );
      final timed = annotateLyrics(
        const LyricsModel(
          syncedLines: <LyricLine>[
            LyricLine(time: Duration(seconds: 2), text: 'कौशल्या दशरथ के नंदन'),
          ],
          plainLyrics: 'कौशल्या दशरथ के नंदन',
        ),
        song,
        source: 'jiosaavn',
      );

      final selected = selectLyricsVariant(
        variants: <LyricsModel>[plain, timed],
        song: song,
        preference: 'auto',
      );

      expect(selected, same(timed));
    });

    test('romanized preference picks the Latin variant', () {
      final selected = selectLyricsVariant(
        variants: <LyricsModel>[original],
        song: song,
        preference: 'romanized',
      );
      expect(selected, isNotNull);
      expect(selected!.isRomanized, isTrue);
      expect(selected.plainLyrics, 'kaushalyaa dasharatha ke nandana');
    });

    test('language preference matches that language', () {
      final selected = selectLyricsVariant(
        variants: <LyricsModel>[romanized, original],
        song: song,
        preference: 'hindi',
      );
      expect(selected, isNotNull);
      expect(selected!.language, 'hindi');
    });

    test('override wins over the default preference', () {
      final selected = selectLyricsVariant(
        variants: <LyricsModel>[romanized, original],
        song: song,
        preference: 'original',
        override: 'romanized',
      );
      expect(selected, same(romanized));
    });

    test('returns null when the requested language is missing', () {
      final selected = selectLyricsVariant(
        variants: <LyricsModel>[original],
        song: song,
        preference: 'english',
      );
      expect(selected, isNull);
    });
  });
}
