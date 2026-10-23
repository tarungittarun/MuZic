/// Strict end-to-end journey through the real app on Android emulators.
///
/// Each step emits a machine-readable PASS/FAIL line. Any failed assertion
/// fails the test and blocks the E2E workflow; network-backed search/playback
/// are deliberately not downgraded to warnings.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:music_player/main.dart' as app;
import 'package:music_player/widgets/media_controller_card.dart';
import 'package:music_player/widgets/mini_player.dart';
import 'package:music_player/widgets/muzic_home_button.dart';
import 'package:music_player/widgets/song_tile.dart';
import 'package:music_player/widgets/visualizer_bars.dart';

final List<String> _failureLog = <String>[];
int _currentStepIndex = 0;
WidgetTester? _activeTester;

String _visibleText() {
  final tester = _activeTester;
  if (tester == null) return '';
  final labels = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final data = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    final trimmed = data.trim().replaceAll('|', '/');
    if (trimmed.isEmpty || labels.contains(trimmed)) continue;
    labels.add(trimmed);
    if (labels.length >= 12) break;
  }
  return labels.join(' / ');
}

void _emit(
  String name, {
  required String status,
  required int ms,
  String detail = '',
}) {
  // ignore: avoid_print
  print('[E2E] step=$name status=$status ms=$ms detail=$detail');
}

Future<void> step(String name, Future<void> Function() action) async {
  _currentStepIndex++;
  final watch = Stopwatch()..start();
  try {
    await action();
    _emit(name, status: 'PASS', ms: watch.elapsedMilliseconds);
  } catch (error) {
    final screen = _visibleText();
    final first = '$error'.split('\n').first;
    final detail = screen.isEmpty ? first : '$first [screen: $screen]';
    _failureLog.add('$name: $detail');
    _emit(name, status: 'FAIL', ms: watch.elapsedMilliseconds, detail: detail);
    rethrow;
  }
}

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
    // Live waveforms and seek animations remain active while music plays.
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  final destination = find.text(label).last;
  expect(destination, findsOneWidget, reason: '$label destination is missing');
  await tester.tap(destination);
  await settle(tester);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // ignore: avoid_print
  print('[E2E] suite=app_flow strict=true');

  testWidgets(
    'MuZic strict end-to-end journey',
    (WidgetTester tester) async {
      _activeTester = tester;
      final bootWatch = Stopwatch()..start();

      await step('cold_start', () async {
        await app.main();
        await tester.pump();
        await waitFor(tester, find.text('Listen your way'),
            timeout: const Duration(seconds: 30));
        await settle(tester);
      });
      _emit('time_to_first_frame', status: 'PASS', ms: bootWatch.elapsedMilliseconds);

      await step('home_discover_feed', () async {
        expect(find.text('Listen your way'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Discover'), findsWidgets);
        expect(find.text('Search'), findsWidgets);
      });

      await step('one_hand_reach_transition', () async {
        final list = find.byType(ListView).first;
        // The page starts at its top. Three firm pulls should smoothly move
        // the page into thumb reach, without the old Last played overlay.
        for (var pull = 0; pull < 3; pull++) {
          await tester.timedDrag(
            list,
            const Offset(0, 440),
            const Duration(milliseconds: 120),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
        await tester.pump(const Duration(milliseconds: 320));
        final transform = tester.widget<Transform>(
          find.byKey(const ValueKey<String>('one-hand-page-transform')),
        );
        expect(transform.transform.getTranslation().y, greaterThan(100),
            reason: 'three pull-downs did not enter one-hand reach');
        expect(find.text('LAST PLAYED'), findsNothing,
            reason: 'one-hand reach must not place a music card in the open area');

        await tester.timedDrag(
          list,
          const Offset(0, -500),
          const Duration(milliseconds: 160),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final restored = tester.widget<Transform>(
          find.byKey(const ValueKey<String>('one-hand-page-transform')),
        );
        expect(restored.transform.getTranslation().y, closeTo(0, 1),
            reason: 'scrolling upward did not smoothly restore the page');
        // Put the Discover page back at its top before checking the search box.
        await tester.timedDrag(
          list,
          const Offset(0, 900),
          const Duration(milliseconds: 180),
        );
        await tester.pump(const Duration(milliseconds: 200));
      });

      await step('home_recommendation_shelves', () async {
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
        expect(found, isTrue, reason: 'no discover or radio shelf rendered');
      });

      await step('search_flow', () async {
        await tester.enterText(find.byType(TextField).first, 'Arijit Singh');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        var rows = 0;
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 400));
          rows = find.byType(SongTile).evaluate().length;
          if (rows > 0) break;
        }
        expect(rows, greaterThan(0), reason: 'artist search returned no songs');
      });

      await step('search_results_structure', () async {
        expect(find.byType(SongTile), findsWidgets);
        expect(
          find.text('Songs').evaluate().isNotEmpty ||
              find.textContaining('results').evaluate().isNotEmpty,
          isTrue,
          reason: 'search results have no section/count information',
        );
      });

      await step('playback_start', () async {
        final rows = find.byType(SongTile);
        expect(rows, findsWidgets);
        await tester.tap(rows.first);
        await waitFor(tester, find.byType(MiniPlayer),
            timeout: const Duration(seconds: 25));
        await settle(tester);
        expect(find.byType(WavySeekBar), findsWidgets,
            reason: 'compact player did not expose the wavy seek control');
        expect(find.byType(ArtworkBackdrop), findsWidgets,
            reason: 'the full-artwork mini-player background is missing');
      });

      await step('media_notification', () async {
        const system = MethodChannel('music_player/system');
        Map<Object?, Object?> report = <Object?, Object?>{};
        for (var attempt = 0; attempt < 20; attempt++) {
          final raw = await system.invokeMethod<Map<Object?, Object?>>(
            'mediaNotificationDiagnostics',
          );
          if (raw != null) report = raw;
          if ((report['postedCount'] as int? ?? 0) > 0) break;
          await tester.pump(const Duration(seconds: 1));
        }
        // ignore: avoid_print
        print('[E2E] notification-report ${report.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
        expect(report['notificationsEnabled'], isTrue,
            reason: 'Android notifications are disabled');
        expect(report['playbackChannelExists'], isTrue,
            reason: 'the playback channel was not created');
        expect(report['smallIconResolves'], isTrue,
            reason: 'the MuZic notification icon is missing');
        expect(report['postedCount'], greaterThan(0),
            reason: 'Android has no MuZic playback notification');
        expect(report['mediaSessionActive'], isTrue,
            reason: 'Android has no active MuZic MediaSession');
        expect(report['playbackServiceRunning'], isTrue,
            reason: 'the foreground playback service is not running');
      });

      await step('now_playing_lock_screen_parity', () async {
        final miniText = find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.byType(Text),
        ).first;
        await tester.tap(miniText);
        await waitFor(tester, find.byType(MediaControllerCard),
            timeout: const Duration(seconds: 8));
        expect(find.text('This phone'), findsOneWidget);
        expect(find.byType(MuZicAppIcon), findsOneWidget);
        expect(find.byType(ArtworkBackdrop), findsWidgets,
            reason: 'the song face card is not rendered behind the controls');
        expect(find.byType(WavySeekBar), findsWidgets);
        expect(find.text('Lyrics'), findsOneWidget);
        expect(find.text('Up next'), findsOneWidget);
      });

      await step('live_waveform_controls', () async {
        final toggle = find.byTooltip('Show live waveform');
        expect(toggle, findsOneWidget);
        await tester.tap(toggle);
        await waitFor(tester, find.text('LIVE WAVEFORM'),
            timeout: const Duration(seconds: 8));
        expect(find.byType(VisualizerBars), findsOneWidget);
        expect(find.byType(AnimatedContainer), findsAtLeastNWidgets(18),
            reason: 'live waveform bars were not rendered');
      });

      await step('lyrics_language_picker', () async {
        final lyrics = find.text('Lyrics');
        await tester.tap(lyrics);
        await settle(tester);
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(deadline) &&
            find.byIcon(Icons.translate_rounded).evaluate().isEmpty &&
            find.textContaining('Lyrics are unavailable').evaluate().isEmpty) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        final translate = find.byIcon(Icons.translate_rounded);
        if (translate.evaluate().isNotEmpty) {
          await tester.tap(translate.first);
          await tester.pump(const Duration(milliseconds: 700));
          expect(
            find.textContaining('ALL LANGUAGES').evaluate().isNotEmpty ||
                find.textContaining('AVAILABLE FOR THIS TRACK')
                    .evaluate()
                    .isNotEmpty,
            isTrue,
            reason: 'lyrics language sheet did not show available choices',
          );
          await tester.tapAt(const Offset(20, 20));
          await tester.pump(const Duration(milliseconds: 350));
        } else {
          expect(find.textContaining('Lyrics are unavailable'), findsOneWidget,
              reason: 'lyrics view neither loaded content nor explained absence');
        }
      });

      await step('settings_sections', () async {
        final closePlayer = find.byTooltip('Close player');
        if (closePlayer.evaluate().isNotEmpty) {
          await tester.tap(closePlayer.first);
          await settle(tester);
        }
        await _tapTab(tester, 'Settings');
        expect(find.text('Settings'), findsWidgets);
        final scrollable = find.byType(Scrollable).first;
        for (final section in <String>[
          'Appearance',
          'Playback',
          'Recommendations',
          'Downloads & storage',
          'Sound Studio',
          'Diagnostics',
        ]) {
          final heading = find.text(section);
          if (heading.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              heading,
              220,
              scrollable: scrollable,
            );
          }
          expect(heading, findsOneWidget,
              reason: 'Settings is missing the $section section');
        }
        await tester.drag(scrollable, const Offset(0, 5000));
        await tester.pump(const Duration(milliseconds: 350));
      });

      await step('sound_studio_toggle', () async {
        final studio = find.text('Sound Studio');
        await tester.ensureVisible(studio);
        await tester.tap(studio);
        await settle(tester);
        final bass = find.widgetWithText(SwitchListTile, 'Bass impact');
        await tester.ensureVisible(bass);
        expect(bass, findsOneWidget);
        await tester.tap(bass);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Impact'), findsOneWidget,
            reason: 'enabling Bass impact did not reveal its adjustment');
        await tester.tap(find.widgetWithText(SwitchListTile, 'Bass impact'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Impact'), findsNothing,
            reason: 'disabling Bass impact did not collapse its adjustment');
      });

      await step('sleep_timer_toggle', () async {
        final heading = find.text('Sleep timer');
        await tester.ensureVisible(heading);
        await tester.tap(heading);
        await settle(tester);
        final timer = find.text('Pause after inactivity');
        await tester.ensureVisible(timer);
        await tester.tap(timer);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Inactivity duration'), findsOneWidget,
            reason: 'sleep timer duration control did not appear');
      });

      await step('diagnostics_capture', () async {
        final heading = find.text('Diagnostics');
        await tester.scrollUntilVisible(
          heading,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(heading);
        await settle(tester);
        final destination = find.text('Diagnostics & logs');
        await tester.ensureVisible(destination);
        await tester.tap(destination);
        await waitFor(tester, find.text('Capture diagnostics'),
            timeout: const Duration(seconds: 8));
        final capture = find.text('Capture diagnostics');
        await tester.tap(capture);
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.textContaining('entries'), findsWidgets,
            reason: 'diagnostics capture did not show its live event count');
        expect(find.text('Copy report'), findsOneWidget);
        expect(find.text('Save to Downloads'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await settle(tester);
      });

      await step('usage_insights', () async {
        await _tapTab(tester, 'Usage');
        expect(find.text('Insights'), findsOneWidget);
        expect(find.text('TIME WITH MUSIC'), findsOneWidget);
        final usageScroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Recent activity'),
          220,
          scrollable: usageScroll,
        );
        await tester.scrollUntilVisible(
          find.textContaining('Private to this device'),
          220,
          scrollable: usageScroll,
        );
        expect(find.textContaining('Private to this device'), findsOneWidget);
      });

      await step('back_from_each_main_destination', () async {
        for (final destination in <String>['Library', 'Settings', 'Usage']) {
          await _tapTab(tester, destination);
          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(find.byType(TextField), findsOneWidget,
              reason: 'Back from $destination did not return to Search');
        }
      });

      await step('single_recents_task', () async {
        const system = MethodChannel('music_player/system');
        final appTasks = await system.invokeMethod<int>('appTaskCount');
        expect(appTasks, 1,
            reason: 'MuZic has more than one Android Recents task');
      });

      // ignore: avoid_print
      print('[E2E] suite_summary steps=$_currentStepIndex failures=${_failureLog.length} strict=true');
      expect(_failureLog, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
