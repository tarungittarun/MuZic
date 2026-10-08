import 'package:flutter_test/flutter_test.dart';
import 'package:auralis_player/services/music_api_service.dart';

void main() {
  test('decrypts a known DES-ECB JioSaavn media URL', () {
    const encrypted =
        'iPPGVzyogeiPwpro65A0eUaQggN+8+J4mteJdeaEeFiCL4nTGWnI3F16SIjtZBIxsc7WJNlKm0HtZ754aGgzDIPzFaL/aK97';
    expect(
      MusicApiService.decryptSaavnMediaUrl(encrypted),
      'https://aac.saavncdn.com/666/487fc075363611f93bb2a8bfc27635f6_96.mp4',
    );
  });
}
