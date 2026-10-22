import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../services/app_log.dart';
import '../services/app_settings_service.dart';
import '../services/audio_effects_service.dart';
import '../services/discover_options.dart';
import '../services/lyrics_language.dart';
import '../services/notification_service.dart';
import '../services/sleep_timer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/muzic_home_button.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.embedded = false, this.onHome, super.key});

  /// True when Settings is a bottom-navigation page rather than a pushed
  /// route. Embedded mode has no route AppBar/back button.
  final bool embedded;
  final VoidCallback? onHome;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    final palette = context.palette;
    final content = ListView(
      padding: EdgeInsets.fromLTRB(18, widget.embedded ? 18 : 8, 18, 28),
      children: <Widget>[
        if (widget.embedded) ...<Widget>[
          Row(
            children: <Widget>[
              MuZicHomeButton(onPressed: widget.onHome ?? () {}),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'MUZIC',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: palette.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Settings',
                      style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
          _ExpandableSettingsSection(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            summary: 'Theme: ${settings.themeMode.name}',
            initiallyExpanded: false,
            child: Column(
              children: <Widget>[
                _ThemeOption(
                  title: 'Follow device',
                  subtitle: 'Use Android’s current appearance.',
                  icon: Icons.brightness_auto_rounded,
                  mode: ThemeMode.system,
                  selected: settings.themeMode == ThemeMode.system,
                  onSelected: settings.setThemeMode,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                _ThemeOption(
                  title: 'Light',
                  subtitle: 'A bright, high-contrast look.',
                  icon: Icons.light_mode_rounded,
                  mode: ThemeMode.light,
                  selected: settings.themeMode == ThemeMode.light,
                  onSelected: settings.setThemeMode,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                _ThemeOption(
                  title: 'Dark',
                  subtitle: 'A comfortable low-light look.',
                  icon: Icons.dark_mode_rounded,
                  mode: ThemeMode.dark,
                  selected: settings.themeMode == ThemeMode.dark,
                  onSelected: settings.setThemeMode,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Lyrics',
            icon: Icons.lyrics_outlined,
            summary: 'Default: ${lyricsLanguageLabel(settings.lyricsLanguage)}',
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 12, 17, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.lyrics_outlined, color: palette.mint),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Text(
                          'Default lyrics language',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chosen automatically when a song starts. You can switch '
                    'the language any time from the lyrics view while a song '
                    'is playing.',
                    style: TextStyle(
                      color: palette.textMuted,
                      height: 1.45,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Language'),
                    subtitle: Text(
                      lyricsLanguageLabel(settings.lyricsLanguage),
                      style: TextStyle(color: palette.accent),
                    ),
                    trailing: const Icon(Icons.expand_more_rounded),
                    onTap: () => _pickLyricsLanguage(context, settings),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Playback & recommendations',
            icon: Icons.play_circle_outline_rounded,
            summary: 'System player and personal mix',
            initiallyExpanded: true,
            child: Column(
              children: <Widget>[
                FutureBuilder<bool>(
                  future: NotificationService.areEnabled(),
                  builder: (context, snapshot) {
                    final granted = snapshot.data ?? false;
                    final pending = snapshot.connectionState !=
                        ConnectionState.done;
                    return ListTile(
                      leading: Icon(
                        granted
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_outlined,
                        color: granted ? palette.mint : palette.accent,
                      ),
                      title: const Text('Notification access'),
                      subtitle: Text(
                        pending
                            ? 'Checking…'
                            : granted
                                ? 'Allowed — the system media player can appear on the lock screen and in Quick Settings.'
                                : 'Blocked — Android hides the media controls. Allow it here.',
                        style: TextStyle(
                          color: granted ? palette.textMuted : palette.accent,
                          fontSize: 12,
                        ),
                      ),
                      trailing: granted
                          ? const Icon(Icons.check_circle_rounded, size: 18)
                          : FilledButton(
                              onPressed: () async {
                                final ok = await NotificationService
                                    .ensurePermission(force: true);
                                if (!ok) {
                                  await NotificationService.openSystemSettings();
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'Notifications allowed — the system media player can now appear.'
                                            : 'Still blocked. Enable notifications for MuZic in system settings.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Allow'),
                            ),
                    );
                  },
                ),
                Divider(height: 1, color: palette.outline),
                ListTile(
                  leading: Icon(Icons.play_circle_outline_rounded,
                      color: palette.textSecondary),
                  title: const Text('System media player'),
                  subtitle: Text(
                    'Open Android’s media controls.',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => NotificationService.openMediaSettings(),
                ),
                Divider(height: 1, color: palette.outline),
                SwitchListTile(
                  value: settings.autoplayRecommendations,
                  secondary: Icon(Icons.auto_awesome_motion_rounded,
                      color: settings.autoplayRecommendations
                          ? palette.accent
                          : palette.textSecondary),
                  title: const Text('Autoplay recommendations'),
                  subtitle: Text(
                    'Adds a personalised mix after your queue. Recommended '
                    'tracks are actual Up next tracks and play in order.',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  onChanged: settings.setAutoplayRecommendations,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Recommendation mix',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Choose how brave the Up next mix is.',
                        style: TextStyle(color: palette.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: const Text('Familiar'),
                            selected: settings.recommendationStyle == 'familiar',
                            onSelected: (_) =>
                                settings.setRecommendationStyle('familiar'),
                          ),
                          ChoiceChip(
                            label: const Text('Balanced'),
                            selected: settings.recommendationStyle == 'balanced',
                            onSelected: (_) =>
                                settings.setRecommendationStyle('balanced'),
                          ),
                          ChoiceChip(
                            label: const Text('Discovery'),
                            selected: settings.recommendationStyle == 'discovery',
                            onSelected: (_) =>
                                settings.setRecommendationStyle('discovery'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: palette.outline),
                ListTile(
                  leading: Icon(Icons.battery_saver_rounded,
                      color: palette.textSecondary),
                  title: const Text('Allow background playback'),
                  subtitle: Text(
                    'Exempt MuZic from battery optimisation so playback '
                    'is not killed (needed on MIUI, ColorOS, FuntouchOS).',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await NotificationService.requestBatteryExemption();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Allow MuZic to run in the background in the '
                            'system dialog to keep playback alive.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Sleep timer',
            icon: Icons.bedtime_outlined,
            summary: settings.sleepTimerEnabled ? '${_sleepLabel(settings.sleepTimerMinutes)} of inactivity' : 'Off',
            initiallyExpanded: false,
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  value: settings.sleepTimerEnabled,
                  secondary: Icon(Icons.bedtime_outlined,
                      color: settings.sleepTimerEnabled
                          ? palette.accent
                          : palette.textSecondary),
                  title: const Text('Pause after inactivity'),
                  subtitle: Text(
                    'A warning appears 5 minutes before MuZic pauses playback '
                    'when nothing has happened in the app.',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  onChanged: (value) {
                    settings.setSleepTimer(enabled: value);
                    context.read<SleepTimerService>().registerActivity();
                  },
                ),
                if (settings.sleepTimerEnabled) ...<Widget>[
                  Divider(height: 1, color: palette.outline),
                  ListTile(
                    leading: Icon(Icons.timer_outlined,
                        color: palette.textSecondary),
                    title: const Text('Inactivity duration'),
                    subtitle: Text(
                      _sleepLabel(settings.sleepTimerMinutes),
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.expand_more_rounded),
                    onTap: () => _pickSleepDuration(context, settings),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Timeline: ${_sleepLabel(settings.sleepTimerMinutes)} '
                      'without activity → warning → 5 more minutes → paused.',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Discover',
            icon: Icons.explore_rounded,
            summary: '${kRegionOptions[settings.region] ?? settings.region} • ${settings.languages.map((code) => kDiscoverLanguageLabel[code] ?? code).join(', ')}',
            initiallyExpanded: false,
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.public_rounded, color: palette.accent),
                  title: const Text('Region'),
                  subtitle: Text(
                    kRegionOptions[settings.region] ?? settings.region,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.expand_more_rounded),
                  onTap: () => _pickRegion(context, settings),
                ),
                Divider(height: 1, color: palette.outline),
                ListTile(
                  leading: Icon(Icons.translate_rounded, color: palette.accent),
                  title: const Text('Languages'),
                  subtitle: Text(
                    settings.languages.isEmpty
                        ? 'English'
                        : settings.languages
                            .map((code) => kDiscoverLanguageLabel[code] ?? code)
                            .join(', '),
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.expand_more_rounded),
                  onTap: () => _pickLanguages(context, settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Audio effects',
            icon: Icons.graphic_eq_rounded,
            summary: 'Virtualizer, bass boost and equalizer',
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    secondary: Icon(Icons.surround_sound_rounded,
                        color: settings.virtualizerEnabled
                            ? palette.accent
                            : palette.textSecondary),
                    title: const Text('Virtualizer (surround)'),
                    subtitle: Text(
                      'Widens the sound stage — closest thing to spatial '
                      'audio on this device.',
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                    value: settings.virtualizerEnabled,
                    onChanged: (value) async {
                      await settings.setVirtualizer(enabled: value);
                      if (!context.mounted) return;
                      await context.read<AudioEffectsService>().apply();
                    },
                  ),
                  if (settings.virtualizerEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: <Widget>[
                          const Text('Strength', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: settings.virtualizerStrength
                                  .clamp(0, 100)
                                  .toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${settings.virtualizerStrength}%',
                              onChanged: (value) => settings.setVirtualizer(
                                enabled: true,
                                strength: value.round(),
                              ),
                              onChangeEnd: (value) =>
                                  context.read<AudioEffectsService>().apply(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                  SwitchListTile(
                    secondary: Icon(Icons.equalizer_rounded,
                        color: settings.bassBoostEnabled
                            ? palette.accent
                            : palette.textSecondary),
                    title: const Text('Bass boost'),
                    subtitle: Text(
                      'Enhances low frequencies.',
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                    value: settings.bassBoostEnabled,
                    onChanged: (value) async {
                      await settings.setBassBoost(enabled: value);
                      if (!context.mounted) return;
                      await context.read<AudioEffectsService>().apply();
                    },
                  ),
                  if (settings.bassBoostEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: <Widget>[
                          const Text('Strength', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: settings.bassBoostStrength
                                  .clamp(0, 100)
                                  .toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${settings.bassBoostStrength}%',
                              onChanged: (value) => settings.setBassBoost(
                                enabled: true,
                                strength: value.round(),
                              ),
                              onChangeEnd: (value) =>
                                  context.read<AudioEffectsService>().apply(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                  SwitchListTile(
                    secondary: Icon(Icons.tune_rounded,
                        color: settings.equalizerEnabled
                            ? palette.accent
                            : palette.textSecondary),
                    title: const Text('Equalizer'),
                    subtitle: Text(
                      'Preset: ${_eqPresetName(settings.equalizerPreset)}',
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                    value: settings.equalizerEnabled,
                    onChanged: (value) async {
                      await settings.setEqualizer(enabled: value);
                      if (!context.mounted) return;
                      await context.read<AudioEffectsService>().apply();
                    },
                  ),
                  if (settings.equalizerEnabled)
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      title: const Text('Preset'),
                      subtitle: Text(_eqPresetName(settings.equalizerPreset)),
                      trailing: const Icon(Icons.expand_more_rounded),
                      onTap: () => _pickEqPreset(context, settings),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Diagnostics',
            icon: Icons.bug_report_outlined,
            summary: settings.diagnosticsEnabled ? 'Capture on' : 'Capture off',
            initiallyExpanded: false,
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  value: settings.diagnosticsEnabled,
                  secondary: Icon(
                    Icons.bug_report_outlined,
                    color: settings.diagnosticsEnabled
                        ? palette.accent
                        : palette.textSecondary,
                  ),
                  title: const Text('Diagnostics capture'),
                  subtitle: Text(
                    settings.diagnosticsEnabled
                        ? 'Recording — turn off to stop and delete captured data.'
                        : 'Off — nothing is recorded.',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  onChanged: (value) async {
                    await settings.setDiagnosticsEnabled(value);
                    AppLog.setEnabled(value);
                    if (value) logInfo('diagnostics', 'capture enabled');
                  },
                ),
                Divider(height: 1, color: palette.outline),
                ListTile(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  ),
                  leading:
                      Icon(Icons.troubleshoot_rounded, color: palette.accent),
                  title: const Text('Diagnostics & logs'),
                  subtitle: Text(
                    'Run checks, review captured events, export a report.',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'Privacy',
            icon: Icons.shield_outlined,
            summary: 'Saved only on this device',
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.shield_outlined, color: palette.mint),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      'Your Usage history and diagnostics logs are saved only '
                      'on this device; ${AppInfo.displayName} does not upload '
                      'them. Search terms are sent to the selected music '
                      'provider when you search. Clear local history from the '
                      'Usage tab at any time.',
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
          const SizedBox(height: 14),
          _ExpandableSettingsSection(
            title: 'About MuZic',
            icon: Icons.info_outline_rounded,
            summary: 'Version ${AppInfo.version}+${AppInfo.buildNumber}',
            initiallyExpanded: false,
            child: ListTile(
              leading: Icon(Icons.graphic_eq_rounded, color: palette.accent),
              title: const Text(AppInfo.displayName),
              subtitle: Text('On-device library and player',
                  style: TextStyle(color: palette.textMuted)),
              trailing: Text('${AppInfo.version}+${AppInfo.buildNumber}',
                  style: TextStyle(color: palette.textMuted, fontSize: 12)),
            ),
          ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: content,
    );
  }

  Future<void> _pickLyricsLanguage(
    BuildContext context,
    AppSettingsService settings,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Default lyrics language',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
            for (final code in kLyricsLanguageOptions)
              ListTile(
                title: Text(lyricsLanguageLabel(code)),
                trailing: settings.lyricsLanguage == code
                    ? Icon(Icons.check_rounded,
                        color: context.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, code),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await settings.setLyricsLanguage(selected);
    }
  }

  String _sleepLabel(int minutes) {
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours hour${hours == 1 ? '' : 's'}' : '$hours h $rest min';
  }

  Future<void> _pickSleepDuration(
    BuildContext context,
    AppSettingsService settings,
  ) async {
    const options = <int>[15, 30, 45, 60, 90, 120, 180];
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Pause after',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ),
            for (final minutes in options)
              ListTile(
                title: Text(_sleepLabel(minutes)),
                trailing: settings.sleepTimerMinutes == minutes
                    ? Icon(Icons.check_rounded, color: context.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, minutes),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await settings.setSleepTimer(minutes: selected);
      if (context.mounted) {
        context.read<SleepTimerService>().registerActivity();
      }
    }
  }

  Future<void> _pickRegion(
    BuildContext context,
    AppSettingsService settings,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Your region',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ),
            for (final entry in kRegionOptions.entries)
              ListTile(
                title: Text(entry.value),
                trailing: settings.region == entry.key
                    ? Icon(Icons.check_rounded, color: context.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await settings.setRegion(selected);
  }

  Future<void> _pickLanguages(
    BuildContext context,
    AppSettingsService settings,
  ) async {
    final options = kDiscoverLanguageLabel.keys.toList(growable: false);
    final chosen = <String>{...settings.languages};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Languages for recommendations',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final code in options)
                      CheckboxListTile(
                        dense: true,
                        value: chosen.contains(code),
                        title: Text(kDiscoverLanguageLabel[code] ?? code),
                        onChanged: (value) {
                          setSheetState(() {
                            if (value == true) {
                              chosen.add(code);
                            } else {
                              chosen.remove(code);
                            }
                          });
                          settings.setLanguages(chosen.toList());
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _eqPresetName(int preset) {
    const names = <String>[
      'Normal',
      'Classical',
      'Dance',
      'Flat',
      'Folk',
      'Heavy metal',
      'Hip hop',
      'Jazz',
      'Pop',
      'Rock',
    ];
    return preset >= 0 && preset < names.length ? names[preset] : 'Normal';
  }

  Future<void> _pickEqPreset(
    BuildContext context,
    AppSettingsService settings,
  ) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Equalizer preset',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
            for (var preset = 0; preset < 10; preset++)
              ListTile(
                title: Text(_eqPresetName(preset)),
                trailing: settings.equalizerPreset == preset
                    ? Icon(Icons.check_rounded,
                        color: context.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, preset),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await settings.setEqualizer(enabled: true, preset: selected);
      if (context.mounted) {
        await context.read<AudioEffectsService>().apply();
      }
    }
  }
}

class _ExpandableSettingsSection extends StatelessWidget {
  const _ExpandableSettingsSection({
    required this.title,
    required this.icon,
    required this.summary,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final String summary;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Keep the section heading visually separate from the controls inside:
    // a raised accent-led header, then a recessed contents panel below it.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: palette.surface,
          child: ExpansionTile(
            key: PageStorageKey<String>('settings-section-$title'),
            initiallyExpanded: initiallyExpanded,
            maintainState: true,
            tilePadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            childrenPadding: EdgeInsets.zero,
            backgroundColor: palette.surface,
            collapsedBackgroundColor: palette.surface,
            iconColor: palette.accent,
            collapsedIconColor: palette.accent,
            shape: Border(bottom: BorderSide(color: palette.outline, width: 0.8)),
            collapsedShape: Border.all(color: palette.outline, width: 0.8),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: <Color>[
                    palette.accent.withValues(alpha: 0.22),
                    palette.mint.withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, color: palette.accent, size: 22),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: palette.textPrimary,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                summary,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            children: <Widget>[
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? palette.background.withValues(alpha: 0.68)
                      : palette.surfaceRaised.withValues(alpha: 0.48),
                  border: Border(
                    top: BorderSide(color: palette.outline, width: 0.8),
                    left: BorderSide(color: palette.accent, width: 3),
                  ),
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.mode,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final ThemeMode mode;
  final bool selected;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      onTap: () => onSelected(mode),
      leading: Icon(icon, color: selected ? palette.accent : palette.textSecondary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: TextStyle(color: palette.textMuted, fontSize: 12)),
      trailing: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: selected ? palette.accent : palette.textMuted,
      ),
    );
  }
}
