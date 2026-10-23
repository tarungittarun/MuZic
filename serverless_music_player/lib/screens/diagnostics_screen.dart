import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_log.dart';
import '../services/app_settings_service.dart';
import '../services/diagnostics_service.dart';
import '../theme/app_theme.dart';

enum _DiagnosticsTimePreset { all, last15Minutes, lastHour, today, custom }

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final Set<LogLevel> _selectedLevels = Set<LogLevel>.of(LogLevel.values);
  _DiagnosticsTimePreset _timePreset = _DiagnosticsTimePreset.all;
  DateTime? _customStart;
  DateTime? _customEnd;

  List<LogEntry> _filteredEntries(List<LogEntry> entries) {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;
    switch (_timePreset) {
      case _DiagnosticsTimePreset.all:
        break;
      case _DiagnosticsTimePreset.last15Minutes:
        start = now.subtract(const Duration(minutes: 15));
        end = now;
      case _DiagnosticsTimePreset.lastHour:
        start = now.subtract(const Duration(hours: 1));
        end = now;
      case _DiagnosticsTimePreset.today:
        start = DateTime(now.year, now.month, now.day);
        end = now;
      case _DiagnosticsTimePreset.custom:
        start = _customStart;
        end = _customEnd;
    }
    return filterLogEntries(
      entries,
      levels: _selectedLevels,
      start: start,
      end: end,
    );
  }

  Future<void> _pickCustomTimeRange() async {
    final now = DateTime.now();
    final initialStart =
        _customStart ?? now.subtract(const Duration(hours: 1));
    final initialEnd = _customEnd ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: 'Choose log dates',
    );
    if (range == null || !mounted) return;
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialStart),
      helpText: 'Exact start time',
    );
    if (startTime == null || !mounted) return;
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialEnd),
      helpText: 'Exact end time',
    );
    if (endTime == null || !mounted) return;
    var start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
      startTime.hour,
      startTime.minute,
    );
    var end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      endTime.hour,
      endTime.minute,
    );
    if (end.isBefore(start)) {
      final swap = start;
      start = end;
      end = swap;
    }
    setState(() {
      _customStart = start;
      _customEnd = end;
      _timePreset = _DiagnosticsTimePreset.custom;
    });
  }

  String _timeRangeLabel() {
    if (_timePreset != _DiagnosticsTimePreset.custom ||
        _customStart == null ||
        _customEnd == null) {
      return '';
    }
    String stamp(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return '${stamp(_customStart!)} → ${stamp(_customEnd!)}';
  }

  @override
  void initState() {
    super.initState();
    AppLog.addListener(_onLog);
  }

  @override
  void dispose() {
    AppLog.removeListener(_onLog);
    super.dispose();
  }

  void _onLog(LogEntry entry) {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = context.watch<DiagnosticsService>();
    final settings = context.watch<AppSettingsService>();
    final palette = context.palette;
    final captureOn = settings.diagnosticsEnabled;
    final allEntries = AppLog.snapshot().reversed.toList(growable: false);
    final entries = _filteredEntries(allEntries);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add marker to the log',
            onPressed: () {
              logInfo('user', 'marker added from diagnostics screen');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Marker added to the log.')),
              );
            },
            icon: const Icon(Icons.flag_outlined),
          ),
          IconButton(
            tooltip: 'Clear captured logs',
            onPressed: () {
              AppLog.clear();
              setState(() {});
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          Card(
            child: SwitchListTile(
              value: captureOn,
              secondary: Icon(
                captureOn ? Icons.analytics_rounded : Icons.analytics_outlined,
                color: captureOn ? palette.mint : palette.textMuted,
              ),
              title: const Text('Capture diagnostics'),
              subtitle: Text(
                captureOn
                    ? 'Recording this device\'s playback activity. Turn off to '
                        'stop capturing and delete what was recorded.'
                    : 'Off — nothing is recorded. Turn on to capture playback, '
                        'network and player events for troubleshooting.',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              onChanged: (value) async {
                await context
                    .read<AppSettingsService>()
                    .setDiagnosticsEnabled(value);
                AppLog.setEnabled(value);
                if (value) {
                  logInfo('diagnostics', 'capture enabled by user');
                }
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 12),
          if (!captureOn)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.lock_outline_rounded, color: palette.mint),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Text(
                            'Diagnostics are off',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'MuZic records nothing unless you switch capture on. '
                      'When enabled it records search and stream resolution '
                      'steps, playback and fallback errors, lyrics lookups, '
                      'queue and settings state — everything needed to '
                      'reproduce a bug. Everything stays on this device until '
                      'you export and share it.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (captureOn) Card(
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.bug_report_outlined, color: palette.mint),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      'Diagnostics records app events on this device only: '
                      'search and stream resolution steps with timings, '
                      'playback and fallback errors, lyrics lookups, settings '
                      'and queue state. Reproduce the problem, then export the '
                      'report and share it for analysis.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'SIMULATE & CAPTURE',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Run simulated checks to exercise the same pipeline a song '
                    'uses (search → stream URL → CDN reachability → lyrics → '
                    'Source B) and capture what happens at each step.',
                    style: TextStyle(
                      color: palette.textMuted,
                      height: 1.45,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: diagnostics.isSimulating
                            ? null
                            : () => _runSimulation(context),
                        icon: diagnostics.isSimulating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_circle_outline_rounded),
                        label: Text(diagnostics.isSimulating
                            ? 'Running checks…'
                            : 'Run simulated checks'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copyReport(context),
                        icon: const Icon(Icons.copy_all_rounded),
                        label: const Text('Copy report'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _saveToDownloads(context),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Save to Downloads'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _saveReport(context),
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('App storage'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _shareReport(context),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share report'),
                      ),
                    ],
                  ),
                  if (diagnostics.lastReportPath != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Last report saved to:\n${diagnostics.lastReportPath}',
                      style: TextStyle(
                        color: palette.mint,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (diagnostics.simulationSteps.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: palette.outline),
                    const SizedBox(height: 10),
                    for (final step in diagnostics.simulationSteps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              step.ok
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded,
                              size: 15,
                              color: step.ok ? palette.mint : palette.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${neutralizeProviderNames(step.name)} · '
                                '${step.elapsed.inMilliseconds} ms\n'
                                '${neutralizeProviderNames(step.detail)}',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (captureOn) Row(
            children: <Widget>[
              Text(
                'CAPTURED LOGS',
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              const Spacer(),
              Text(
                captureOn
                    ? 'live · ${AppLog.entries.length} entries'
                    : 'capture off',
                style: TextStyle(
                  color: captureOn ? palette.mint : palette.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (captureOn) ...<Widget>[
            Text(
              'LOG TYPE',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final level in LogLevel.values)
                  FilterChip(
                    label: Text(level.name.toUpperCase()),
                    selected: _selectedLevels.contains(level),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedLevels.add(level);
                        } else {
                          _selectedLevels.remove(level);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'TIME',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All time'),
                  selected: _timePreset == _DiagnosticsTimePreset.all,
                  onSelected: (_) => setState(
                    () => _timePreset = _DiagnosticsTimePreset.all,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Last 15 min'),
                  selected:
                      _timePreset == _DiagnosticsTimePreset.last15Minutes,
                  onSelected: (_) => setState(
                    () => _timePreset =
                        _DiagnosticsTimePreset.last15Minutes,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Last hour'),
                  selected: _timePreset == _DiagnosticsTimePreset.lastHour,
                  onSelected: (_) => setState(
                    () => _timePreset = _DiagnosticsTimePreset.lastHour,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _timePreset == _DiagnosticsTimePreset.today,
                  onSelected: (_) => setState(
                    () => _timePreset = _DiagnosticsTimePreset.today,
                  ),
                ),
                ActionChip(
                  avatar: Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: _timePreset == _DiagnosticsTimePreset.custom
                        ? palette.mint
                        : palette.textMuted,
                  ),
                  label: const Text('Exact time…'),
                  onPressed: () => _pickCustomTimeRange(),
                ),
              ],
            ),
            if (_timeRangeLabel().isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              Text(
                _timeRangeLabel(),
                style: TextStyle(
                  color: palette.mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Showing ${entries.length} of ${allEntries.length} captured entries',
              style: TextStyle(color: palette.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 6),
          ],
          if (captureOn && entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  allEntries.isEmpty
                      ? 'No logs captured yet.'
                      : 'No logs match the selected type/time filters.',
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            )
          else if (captureOn)
            for (final entry in entries.take(200)) _LogTile(entry: entry),
        ],
      ),
    );
  }

  Future<void> _runSimulation(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final diagnostics = context.read<DiagnosticsService>();
    await diagnostics.runSimulation();
    final failures = diagnostics.simulationSteps.where((s) => !s.ok).length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(failures == 0
            ? 'Simulated checks finished — all steps passed.'
            : 'Simulated checks finished — $failures step(s) failed. '
                'Export the report for details.'),
      ),
    );
  }

  Future<void> _copyReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final diagnostics = context.read<DiagnosticsService>();
    final report = diagnostics.clipboardReport();
    await Clipboard.setData(ClipboardData(text: report));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Report copied to clipboard (${report.length} characters).',
        ),
      ),
    );
  }

  Future<void> _saveToDownloads(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final diagnostics = context.read<DiagnosticsService>();
    final path = await diagnostics.saveToDownloads();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          path.isEmpty
              ? 'Could not save the report to Downloads.'
              : 'Report saved to $path',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _saveReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final diagnostics = context.read<DiagnosticsService>();
    final path = await diagnostics.exportReport();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Report saved to:\n$path'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _shareReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final diagnostics = context.read<DiagnosticsService>();
    final shared = await diagnostics.shareReport();
    if (!shared) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Sharing is unavailable here — use Copy or Save instead.',
          ),
        ),
      );
    }
  }
}

/// Keeps provider URLs and brand names out of diagnostics displayed in the UI.
/// The full technical details remain available in the exported diagnostics file.
String neutralizeProviderNames(String value) {
  return value
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), 'network link')
      .replaceAll(
        RegExp(
          r'\b(?:[\w-]+\.)*(?:saavncdn\.com|jiosaavn\.com|googlevideo\.com|youtube\.com|ytimg\.com|lrclib\.net|radioparadise\.com)\b',
          caseSensitive: false,
        ),
        'media host',
      )
      .replaceAll(
        RegExp(r'radio\s*paradise', caseSensitive: false),
        'radio source',
      )
      .replaceAll(RegExp('googlevideo', caseSensitive: false), 'media host')
      .replaceAll(RegExp('jiosaavn', caseSensitive: false), 'Source A')
      .replaceAll(RegExp('youtube', caseSensitive: false), 'Source B')
      .replaceAll(RegExp('lrclib', caseSensitive: false), 'lyrics source')
      .replaceAll(RegExp('spotify', caseSensitive: false), 'radio mix')
      .replaceAll(
        RegExp(
          r'\b(?:motorola|samsung|xiaomi|oppo|vivo|oneplus|miui|color\s*os|funtouch\s*os|hyper\s*os|one\s*ui|hello\s*ui|google|apple|amazon|microsoft|chrome|safari|iphone|ipad|ios)\b',
          caseSensitive: false,
        ),
        'device',
      )
      .replaceAll(RegExp('android', caseSensitive: false), 'system');
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (entry.level) {
      LogLevel.error => palette.accent,
      LogLevel.warn => Colors.orangeAccent,
      LogLevel.info => palette.textSecondary,
      LogLevel.debug => palette.textMuted,
    };
    final time =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
    final logLine = neutralizeProviderNames(
      '$time ${entry.level.name.toUpperCase()} [${entry.category}] '
      '${entry.message}'
      '${entry.data.isEmpty ? '' : ' ${entry.data}'}',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          logLine,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            height: 1.45,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
