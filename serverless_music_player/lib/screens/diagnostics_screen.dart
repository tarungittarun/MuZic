import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_log.dart';
import '../services/app_settings_service.dart';
import '../services/diagnostics_service.dart';
import '../theme/app_theme.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
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
    final entries = AppLog.snapshot().reversed.toList(growable: false);
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
                    'YouTube) and capture what happens at each step.',
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
                                '${step.name} · ${step.elapsed.inMilliseconds} ms\n'
                                '${step.detail}',
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
          if (captureOn && entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No logs captured yet.',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$time ${entry.level.name.toUpperCase()} [${entry.category}] '
          '${entry.message}'
          '${entry.data.isEmpty ? '' : ' ${entry.data}'}',
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
