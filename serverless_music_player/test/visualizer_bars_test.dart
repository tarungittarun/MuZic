import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/theme/app_theme.dart';
import 'package:music_player/widgets/visualizer_bars.dart';

void main() {
  testWidgets('live waveform bars react to changing audio energy',
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

    double tallestBar() {
      var tallest = 0.0;
      for (var index = 0; index < 18; index++) {
        final bar = find.byKey(ValueKey<String>('visualizer-bar-$index'));
        final height = tester.getSize(bar).height;
        if (height > tallest) tallest = height;
      }
      return tallest;
    }

    final idleHeight = tallestBar();
    bands.add(List<double>.filled(18, 0.92));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final loudHeight = tallestBar();
    expect(loudHeight, greaterThan(idleHeight + 10));

    bands.add(List<double>.filled(18, 0.08));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(tallestBar(), lessThan(loudHeight - 4));
  });
}
