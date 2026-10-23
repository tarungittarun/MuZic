import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/theme/app_theme.dart';
import 'package:music_player/widgets/visualizer_bars.dart';

void main() {
  test('waveform smoothing follows loud and quiet audio bands', () {
    final idle = List<double>.filled(18, 0.055);
    final loud = smoothVisualizerLevels(
      previous: idle,
      incoming: List<double>.filled(18, 0.92),
      barCount: 18,
    );
    final quiet = smoothVisualizerLevels(
      previous: loud,
      incoming: List<double>.filled(18, 0.08),
      barCount: 18,
    );

    expect(loud, hasLength(18));
    expect(loud.first, greaterThan(0.5));
    expect(quiet.first, lessThan(loud.first));
    expect(quiet.first, greaterThan(0.055));
  });

  testWidgets('live visualizer renders a bar for every audio band',
      (tester) async {
    final bands = StreamController<List<double>>.broadcast();
    addTearDown(bands.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(child: VisualizerBars(bands: bands.stream)),
        ),
      ),
    );

    expect(find.byType(VisualizerBars), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNWidgets(18));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
