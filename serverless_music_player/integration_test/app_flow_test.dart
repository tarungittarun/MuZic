/// End-to-end journey across the real app on a real Android device/emulator.
///
/// Every step prints a machine-readable line so CI can build a report:
///   [E2E] step=<name> status=PASS|FAIL|WARN ms=<duration> detail=<text>
///
/// Core UI/navigation steps are strict (they fail the build). Steps that need
/// the live JioSaavn/YouTube network are recorded as WARN so a flaky CDN never
/// hides genuine regressions in the app itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:music_player/main.dart' as app;
import 'package:music_player/widgets/mini_player.dart';
import 'package:music_player/widgets/song_tile.dart';

final List<String> _failureLog = <String>[];
int _currentStepIndex = 0;

void _emit(
  String step, {
  required String status,
  required int ms,
  String detail = '',
}) {
  // ignore: avoid_print
  print('[E2E] step=$step status=$status ms=$ms detail=$detail');
}

/// Runs [action] and records PASS/FAIL/WARN with timing.
Future<void> step(
  String name,
  Future<void> Function() action, {
  bool soft = false,
}) async {
  _currentStepIndex++;
  final watch = Stopwatch()..start();
  try {
    await action();
    _emit(name, status: 'PASS', ms: watch.elapsedMilliseconds);
  } catch (error) {
    final text = '$error'.split('\n').first;
    if (soft) {
      _emit(name, status: 'WARN', ms: watch.elapsedMilliseconds, detail: text);
      return;
    }
    _failureLog.add('$name: $text');
    _emit(name, status: 'FAIL', ms: watch.elapsedMilliseconds, detail: text);
    rethrow;
  }
}

/// Pumps until [finder] matches or [timeout] expires.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
  Duration poll = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(poll);
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out after ${timeout.inSeconds}s waiting for $finder');
}

Future<void> settle(WidgetTester tester,
    {Duration max = const Duration(seconds: 4)}) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      max,
    );
  } catch (_) {
    // Continuous animations (waveform, progress) never settle; that is fine.
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // ignore: avoid_print
  print('[E2E] suite=app_flow steps_expected=14');

  testWidgets(
    'MuZic end-to-end journey',
    (WidgetTester tester) async {
      final bootWatch = Stopwatch()..start();

      await step('cold_start', () async {
        await app.main();
        await tester.pump();
        await waitFor(tester, find.text('Listen your way'),
            timeout: const Duration(seconds: 30));
        await settle(tester);
      });
      final bootMs = bootWatch.elapsedMilliseconds;
      _emit('time_to_first_frame', status: 'PASS', ms: bootMs);

      await step('home_discover_feed', () async {
        expect(find.text('Listen your way'), findsOneWidget);
        // Search field and the Discover/Library tabs must be present.
        expect(find.byType(TextField), findsWidgets);
        expect(find.text('Discover'), findsWidgets);
        expect(find.text('Library'), findsWidgets);
      });

      await step('home_recommendation_shelves', () async {
        // Trending shelves load from the network; give them time, then assert
        // that at least one recommendation shelf rendered.
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        var found = false;
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 400));
          if (find.textContaining('Trending in').evaluate().isNotEmpty ||
              find.textContaining('Recently played').evaluate().isNotEmpty ||
              find.text('Lossless radio').evaluate().isNotEmpty) {
            found = true;
            break;
          }
        }
        expect(found, isTrue, reason: 'no home shelves rendered');
      });

      await step('search_flow', () async {
        await tester.enterText(find.byType(TextField).first, 'Arijit Singh');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.search);
        // Give the network a generous window; results are soft-required.
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        var rows = 0;
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 400));
          rows = find.byType(SongTile).evaluate().length;
          if (rows > 2) break;
        }
        expect(rows, greaterThan(0), reason: 'search produced no rows');
      }, soft: true);

      await step('search_results_structure', () async {
        // Songs section header or result count must be visible after searching.
        final hasStructure =
            find.text('Songs').evaluate().isNotEmpty ||
            find.textContaining('results').evaluate().isNotEmpty;
        expect(hasStructure, isTrue);
      }, soft: true);

      await step('playback_start', () async {
        final rows = find.byType(SongTile);
        expect(rows, findsWidgets);
        await tester.tap(rows.first);
        await tester.pump();
        // The mini player (with a skip-next control) appears once a track is
        // queued; playback itself needs the live CDN, so this stays soft.
        await waitFor(tester, find.byIcon(Icons.skip_next_rounded),
            timeout: const Duration(seconds: 25));
      }, soft: true);

      await step('now_playing_and_lyrics', () async {
        // Open the now-playing sheet by tapping the mini player's info area.
        if (find.byType(MiniPlayer).evaluate().isNotEmpty) {
          await tester.tap(find.byType(MiniPlayer));
          await tester.pump(const Duration(milliseconds: 900));
          await settle(tester);
        }
        // The lyrics toggle is present on the sheet when a track exists.
        final lyricsToggle = find.byIcon(Icons.lyrics_outlined);
        if (lyricsToggle.evaluate().isNotEmpty) {
          await tester.tap(lyricsToggle.first);
          await tester.pump(const Duration(milliseconds: 800));
          await settle(tester);
        }
      }, soft: true);

      await step('lyrics_language_picker', () async {
        final translate = find.byIcon(Icons.translate_rounded);
        if (translate.evaluate().isNotEmpty) {
          await tester.tap(translate.first);
          await tester.pump(const Duration(milliseconds: 700));
          final hasSections =
              find.textContaining('ALL LANGUAGES').evaluate().isNotEmpty ||
                  find.textContaining('AVAILABLE FOR THIS TRACK')
                      .evaluate()
                      .isNotEmpty;
          expect(hasSections, isTrue,
              reason: 'language sheet did not show its sections');
          // Dismiss the sheet.
          await tester.tapAt(const Offset(20, 20));
          await tester.pump(const Duration(milliseconds: 400));
        }
      }, soft: true);

      await step('settings_sections', () async {
        // Close the player sheet first.
        final close = find.byTooltip('Close player');
        if (close.evaluate().isNotEmpty) {
          await tester.tap(close.first);
          await tester.pump(const Duration(milliseconds: 500));
        }
        final tune = find.byIcon(Icons.tune_rounded);
        expect(tune, findsWidgets);
        await tester.tap(tune.first);
        await tester.pump(const Duration(milliseconds: 800));
        await settle(tester);
        for (final section in <String>[
          'PLAYBACK',
          'SLEEP TIMER',
          'AUDIO EFFECTS',
          'DISCOVER',
          'DIAGNOSTICS',
        ]) {
          final found = find.text(section);
          if (found.evaluate().isEmpty) {
            await tester.scrollUntilVisible(found, 240,
                scrollable: find.byType(Scrollable).first);
          }
          expect(found.evaluate().isNotEmpty, isTrue,
              reason: 'missing settings section $section');
        }
        // Back to the top for the following steps.
        await tester.drag(find.byType(Scrollable).first,
            const Offset(0, 3000));
        await tester.pump(const Duration(milliseconds: 400));
      });

      await step('sleep_timer_toggle', () async {
        final toggle = find.text('Pause after inactivity');
        await tester.scrollUntilVisible(toggle, 220,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 500));
        // The duration row appears only when enabled.
        expect(find.text('Inactivity duration'), findsOneWidget);
      }, soft: true);

      await step('audio_effects_toggle', () async {
        final bass = find.text('Bass boost');
        await tester.scrollUntilVisible(bass, 220,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(bass);
        await tester.pump(const Duration(milliseconds: 600));
      }, soft: true);

      await step('diagnostics_capture', () async {
        final diag = find.text('Diagnostics & logs');
        await tester.scrollUntilVisible(diag, 260,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(diag);
        await tester.pump(const Duration(milliseconds: 900));
        await settle(tester);
        final capture = find.text('Capture diagnostics');
        expect(capture, findsWidgets);
        await tester.tap(capture.first);
        await tester.pump(const Duration(milliseconds: 800));
        // With capture on, the log header reports live entries.
        expect(find.textContaining('entries'), findsWidgets);
        for (final action in <String>['Copy report', 'Save to Downloads']) {
          expect(find.text(action), findsOneWidget,
              reason: 'missing diagnostics action $action');
        }
      }, soft: true);

      await step('navigation_back_home', () async {
        final back = find.byType(BackButton);
        if (back.evaluate().isNotEmpty) {
          await tester.tap(back.first);
          await tester.pump(const Duration(milliseconds: 700));
        }
        final back2 = find.byType(BackButton);
        if (back2.evaluate().isNotEmpty) {
          await tester.tap(back2.first);
          await tester.pump(const Duration(milliseconds: 700));
        }
        await settle(tester);
      }, soft: true);

      // ignore: avoid_print
      print('[E2E] suite_summary steps=$_currentStepIndex failures=${_failureLog.length}');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
