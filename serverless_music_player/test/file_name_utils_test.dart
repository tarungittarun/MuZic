import 'package:flutter_test/flutter_test.dart';
import 'package:muzic/utils/file_name_utils.dart';

void main() {
  group('track filenames', () {
    test('uses a sanitized song title plus its extension only', () {
      expect(trackFileName('Naa/Ready: Live?', '.m4a'), 'Naa Ready Live.m4a');
      expect(trackFileName('Aashiqui 2', 'mp4'), 'Aashiqui 2.mp4');
    });

    test('does not expose provider labels in exported filenames', () {
      expect(
        trackFileName('YouTube Music - JioSaavn - Song Name', 'mp3'),
        'Song Name.mp3',
      );
      expect(trackFileName('Radio Paradise', 'mp4'), 'Unknown track.mp4');
      expect(trackFileName('youtube_explode_dart - Another Song', 'mp3'),
          'Another Song.mp3');
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
