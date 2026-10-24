import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/utils/file_name_utils.dart';

void main() {
  group('track filenames', () {
    test('uses a sanitized song title plus its extension only', () {
      expect(trackFileName('Naa/Ready: Live?', '.m4a'), 'Naa Ready Live.m4a');
      expect(trackFileName('Aashiqui 2', 'mp4'), 'Aashiqui 2.mp4');
    });

    test('keeps Unicode titles and provides a safe fallback', () {
      expect(trackFileName('ನೀನೆ ನೀನೆ', '.mp3'), 'ನೀನೆ ನೀನೆ.mp3');
      expect(trackFileName('...\u0000', '.m4a'), 'Unknown track.m4a');
    });

    test('bounds exceptionally long titles without cutting Unicode runes', () {
      final title = '${List<String>.filled(95, 'A').join()}🎵🎵';
      final name = trackFileName(title, '.m4a');
      expect(name.endsWith('.m4a'), isTrue);
      expect(name.runes.length, 100);
    });
  });
}
