import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/song_model.dart';
import 'package:music_player/widgets/media_controller_card.dart';
import 'package:music_player/widgets/muzic_home_button.dart';

const SongModel _song = SongModel(
  id: 'card-1',
  sourceId: 'card-1',
  title: 'Chhod Diya',
  artist: 'Arijit Singh',
  source: SongSource.jioSaavn,
  durationMs: 300000,
);

void main() {
  testWidgets('lock-screen-style card shows face-card chrome and metadata',
      (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 420,
              child: MediaControllerCard(
                song: _song,
                isPlaying: true,
                isBusy: false,
                position: const Duration(seconds: 71),
                duration: const Duration(minutes: 5),
                onPlayPause: () => toggles++,
                onNext: () {},
                onPrevious: () {},
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    // Same chrome as Android's system media card: MuZic icon top-left,
    // "This phone" output pill, title/artist overlaid on the artwork.
    expect(find.byType(MuZicAppIcon), findsOneWidget);
    expect(find.byType(ArtworkBackdrop), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Chhod Diya'), findsOneWidget);
    expect(find.text('Arijit Singh'), findsOneWidget);
    expect(find.text('1:11'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    expect(toggles, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wavy seek bar reports seeks against the duration',
      (tester) async {
    Duration? sought;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: WavySeekBar(
                position: Duration.zero,
                duration: const Duration(minutes: 4),
                onSeek: (value) => sought = value,
              ),
            ),
          ),
        ),
      ),
    );
    final slider = tester.getCenter(find.byType(Slider));
    await tester.tapAt(slider);
    expect(sought, isNotNull);
    expect(sought!.inSeconds, greaterThan(100));
    expect(sought!.inSeconds, lessThan(140));
  });

  testWidgets('wavy seek animation moves while playback is active',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: WavySeekBar(
                position: const Duration(seconds: 90),
                duration: const Duration(minutes: 4),
                isPlaying: true,
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    WavySliderTrackShape shape() =>
        tester.widget<SliderTheme>(find.byType(SliderTheme)).data.trackShape!
            as WavySliderTrackShape;

    final initialPhase = shape().phase;
    await tester.pump(const Duration(milliseconds: 240));
    expect(shape().phase, isNot(initialPhase));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
