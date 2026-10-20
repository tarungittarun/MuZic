import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../models/song_model.dart';
import '../providers/player_controller.dart';
import 'app_log.dart';
import 'app_settings_service.dart';
import 'library_service.dart';
import 'music_api_service.dart';
import 'usage_service.dart';

/// A single completed step of the simulated diagnostics run.
class SimulationStep {
  SimulationStep({
    required this.name,
    required this.ok,
    required this.elapsed,
    required this.detail,
  });

  final String name;
  final bool ok;
  final Duration elapsed;
  final String detail;

  @override
  String toString() {
    final status = ok ? 'OK' : 'FAILED';
    return '[$status] $name (${elapsed.inMilliseconds} ms): $detail';
  }
}

/// Captures diagnostics data, runs simulated pipeline checks, and exports a
/// shareable report with everything needed to analyse a playback problem.
class DiagnosticsService extends ChangeNotifier {
  DiagnosticsService({
    required this.settings,
    required this.library,
    required this.usage,
    required this.player,
    required this.musicApi,
  });

  final AppSettingsService settings;
  final LibraryService library;
  final UsageService usage;
  final PlayerController player;
  final MusicApiService musicApi;

  final List<SimulationStep> _steps = <SimulationStep>[];
  bool _simulating = false;
  String? _lastReportPath;

  bool get isSimulating => _simulating;
  List<SimulationStep> get simulationSteps => List<SimulationStep>.of(_steps);
  String? get lastReportPath => _lastReportPath;
  int get capturedLogCount => AppLog.entries.length;

  /// Runs a simulated end-to-end pipeline (search → stream URL → CDN probe →
  /// lyrics) capturing timing and errors for every step. Playback itself is
  /// left untouched so listening is never interrupted.
  Future<List<SimulationStep>> runSimulation() async {
    if (_simulating) return simulationSteps;
    _simulating = true;
    _steps.clear();
    notifyListeners();
    logInfo('diagnostics', 'simulation started');

    SongModel? probeSong;
    String? probeUrl;

    await _timed('JioSaavn search', () async {
      final results = await musicApi.searchJioSaavn('test song', limit: 3);
      if (results.isEmpty) {
        return 'No results returned.';
      }
      probeSong = results.first;
      final hasUrl = probeSong!.streamUrl != null;
      return '${results.length} results; first="${probeSong!.title}" '
          'hasStreamUrl=$hasUrl language=${probeSong!.language}';
    });

    if (probeSong != null) {
      await _timed('Stream URL resolve', () async {
        probeUrl = await musicApi.resolveStream(probeSong!);
        final host = Uri.tryParse(probeUrl!)?.host ?? '?';
        return 'Resolved host=$host';
      });

      if (probeUrl != null) {
        await _timed('CDN reachability', () async {
          final response = await http.Client()
              .get(
                Uri.parse(probeUrl!),
                headers: const <String, String>{'Range': 'bytes=0-1023'},
              )
              .timeout(const Duration(seconds: 15));
          final length = response.contentLength ?? -1;
          return 'HTTP ${response.statusCode}; contentLength=$length; '
              'contentType=${response.headers['content-type'] ?? '?'}';
        });
      }

      await _timed('Lyrics variants', () async {
        final bundle = await musicApi.fetchLyricsVariants(probeSong!);
        if (bundle.isEmpty) return 'No lyrics found in any language.';
        return bundle.variants
            .where((variant) => !variant.isEmpty)
            .map((variant) => variant.displayLabel)
            .join(' | ');
      });
    }

    await _timed('YouTube search', () async {
      final results = await musicApi.searchYouTube('lofi beats', limit: 1);
      if (results.isEmpty) return 'No YouTube results.';
      return 'First="${results.first.title}"';
    });

    await _timed('Player state snapshot', () async {
      final song = player.currentSong;
      return 'playing=${player.isPlaying} buffering=${player.isBuffering} '
          'resolving=${player.isResolving} queue=${player.queue.length} '
          'current=${song?.title ?? '(none)'} '
          'position=${player.position.inSeconds}s';
    });

    logInfo('diagnostics', 'simulation finished', <String, Object?>{
      'steps': _steps.length,
      'failures': _steps.where((step) => !step.ok).length,
    });
    _simulating = false;
    notifyListeners();
    return simulationSteps;
  }

  Future<void> _timed(
    String name,
    Future<String> Function() body,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final detail = await body();
      stopwatch.stop();
      _steps.add(SimulationStep(
        name: name,
        ok: true,
        elapsed: stopwatch.elapsed,
        detail: detail,
      ));
      logInfo('diagnostics', 'sim: $name', <String, Object?>{
        'status': 'ok',
        'ms': stopwatch.elapsedMilliseconds,
        'detail': detail,
      });
    } catch (error) {
      stopwatch.stop();
      _steps.add(SimulationStep(
        name: name,
        ok: false,
        elapsed: stopwatch.elapsed,
        detail: '$error',
      ));
      logError('diagnostics', 'sim: $name', <String, Object?>{
        'status': 'failed',
        'ms': stopwatch.elapsedMilliseconds,
        'error': '$error',
      });
    }
    notifyListeners();
  }

  /// Builds the plain-text diagnostics report.
  String buildReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== ${AppInfo.displayName} diagnostics report ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln(
        'App: ${AppInfo.displayName} ${AppInfo.version}+${AppInfo.buildNumber}');
    buffer.writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Processors: ${Platform.numberOfProcessors}');
    buffer.writeln('Capture enabled: ${settings.diagnosticsEnabled}');
    buffer.writeln('Log entries: ${AppLog.entries.length}');
    buffer.writeln();
    buffer.writeln('--- Settings ---');
    buffer.writeln('themeMode: ${settings.themeMode.name}');
    buffer.writeln('lyricsLanguage: ${settings.lyricsLanguage}');
    buffer.writeln('virtualizer: ${settings.virtualizerEnabled} '
        '(${settings.virtualizerStrength}%)');
    buffer.writeln('bassBoost: ${settings.bassBoostEnabled} '
        '(${settings.bassBoostStrength}%)');
    buffer.writeln('equalizer: ${settings.equalizerEnabled} '
        '(preset ${settings.equalizerPreset})');
    buffer.writeln();
    buffer.writeln('--- Library ---');
    buffer.writeln('favorites: ${library.favoriteSongs.length}');
    buffer.writeln('downloads: ${library.downloadedSongs.length}');
    buffer.writeln('recents: ${library.recentSongs.length}');
    buffer.writeln('playlists: ${library.playlists.length}');
    buffer.writeln();
    buffer.writeln('--- Player ---');
    final song = player.currentSong;
    buffer.writeln('currentSong: ${song == null ? '(none)' : song.title}');
    if (song != null) {
      buffer.writeln('currentSongId: ${song.id}');
      buffer.writeln('currentSource: ${song.source.name}');
      buffer.writeln('currentStreamUrl: ${song.streamUrl ?? '(unresolved)'}');
    }
    buffer.writeln('playing: ${player.isPlaying}');
    buffer.writeln('buffering: ${player.isBuffering}');
    buffer.writeln('resolving: ${player.isResolving}');
    buffer.writeln('position: ${player.position}');
    buffer.writeln('duration: ${player.duration}');
    buffer.writeln('queueLength: ${player.queue.length}');
    for (var i = 0; i < player.queue.length; i++) {
      final item = player.queue[i];
      final marker = i == player.currentIndex ? '*' : ' ';
      buffer.writeln(
          '  $marker [$i] ${item.title} — ${item.artist} (${item.source.name})');
    }
    buffer.writeln();
    buffer.writeln('--- Usage summary (local) ---');
    buffer.writeln('searches: ${usage.searches}');
    buffer.writeln('playStarts: ${usage.playStarts}');
    buffer.writeln('lyricsChecks: ${usage.lyricsChecks}');
    buffer.writeln('listeningTime: ${usage.listeningTime}');
    buffer.writeln();
    if (_steps.isNotEmpty) {
      buffer.writeln('--- Simulation steps ---');
      for (final step in _steps) {
        buffer.writeln(step.toString());
      }
      buffer.writeln();
    }
    final entries = AppLog.snapshot();
    buffer.writeln('--- Log buffer (${entries.length} entries) ---');
    for (final entry in entries) {
      buffer.writeln(entry.format());
    }
    return buffer.toString();
  }

  /// Writes the report to app storage and returns the file path.
  Future<String> exportReport() async {
    final report = buildReport();
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/diagnostics');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${directory.path}/music_diagnostics_$stamp.txt');
    await file.writeAsString(report, flush: true);
    _lastReportPath = file.path;
    logInfo('diagnostics', 'report exported', <String, Object?>{
      'path': file.path,
      'bytes': report.length,
    });
    notifyListeners();
    return file.path;
  }
}
