import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:muzic/providers/player_controller.dart';

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

    test('repeat labels explain queue repeat versus one-track repeat', () {
      expect(PlayerController.repeatModeLabel(LoopMode.off), 'Repeat off');
      expect(PlayerController.repeatModeLabel(LoopMode.all), 'Repeat all');
      expect(PlayerController.repeatModeLabel(LoopMode.one), 'Repeat 1');
      expect(
        PlayerController.repeatModeDescription(LoopMode.all),
        contains('every track in the queue'),
      );
      expect(
        PlayerController.repeatModeDescription(LoopMode.one),
        contains('current track'),
      );
    });
  });
}
