import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../services/app_settings_service.dart';
import '../services/audio_effects_service.dart';
import '../services/lyrics_language.dart';
import '../theme/app_theme.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          Text(
            'APPEARANCE',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
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
          const SizedBox(height: 24),
          Text(
            'LYRICS',
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
              padding: const EdgeInsets.fromLTRB(17, 12, 17, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.lyrics_outlined, color: palette.mint),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          'Default lyrics language',
                          style: const TextStyle(
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
          const SizedBox(height: 24),
          Text(
            'AUDIO EFFECTS',
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
          const SizedBox(height: 24),
          Text(
            'DIAGNOSTICS',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DiagnosticsScreen(),
                ),
              ),
              leading: Icon(Icons.bug_report_outlined, color: palette.accent),
              title: const Text('Diagnostics & log capture'),
              subtitle: Text(
                'Simulate playback steps, capture logs, export a report.',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'PRIVACY',
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
          const SizedBox(height: 24),
          Text(
            'ABOUT',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
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
      ),
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
