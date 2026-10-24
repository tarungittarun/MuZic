import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_player/providers/player_controller.dart';

void main() {
  group('playback mode controls', () {
    test('shuffle toggles on and off', () {
      expect(PlayerController.nextShuffleState(false), isTrue);
      expect(PlayerController.nextShuffleState(true), isFalse);
    });

    test('repeat cycles off, all, one, off', () {
      expect(PlayerController.nextRepeatMode(LoopMode.off), LoopMode.all);
      expect(PlayerController.nextRepeatMode(LoopMode.all), LoopMode.one);
      expect(PlayerController.nextRepeatMode(LoopMode.one), LoopMode.off);
    });
  });
}
