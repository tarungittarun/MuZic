import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';

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
                      'Your Usage history is saved only on this device; Auralis does not upload the stored event log. Search terms are sent to the selected music provider when you search. Clear local history from the Usage tab at any time.',
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
              title: const Text('Auralis'),
              subtitle: Text('On-device library and player', style: TextStyle(color: palette.textMuted)),
              trailing: Text('1.0.0', style: TextStyle(color: palette.textMuted, fontSize: 12)),
            ),
          ),
        ],
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
