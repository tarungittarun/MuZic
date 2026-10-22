import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sleep_timer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'usage_dashboard_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  int _searchFocusTick = 0;
  int _homeResetTick = 0;

  void _selectTab(int index) {
    if (index == 0 && _tab == 0) {
      // A second tap on Search means “put me in the search box”, with the
      // keyboard open and the existing text selected for replacement.
      setState(() => _searchFocusTick++);
      return;
    }
    setState(() => _tab = index);
  }

  void _goHome() {
    setState(() {
      _tab = 0;
      _homeResetTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sleepTimer = context.watch<SleepTimerService>();
    // Any touch anywhere in the app counts as "the user is still here".
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => sleepTimer.registerActivity(),
      child: _scaffold(palette, sleepTimer),
    );
  }

  Widget _scaffold(AppPalette palette, SleepTimerService sleepTimer) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: <Widget>[
            HomeScreen(
              searchFocusTick: _searchFocusTick,
              homeResetTick: _homeResetTick,
            ),
            LibraryScreen(onHome: _goHome),
            SettingsScreen(embedded: true, onHome: _goHome),
            UsageDashboardScreen(onHome: _goHome),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: palette.background,
            border: Border(top: BorderSide(color: palette.outline, width: 0.7)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const MiniPlayer(),
              SizedBox(
                height: 64,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: <Widget>[
                      _BottomDestination(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        selected: _tab == 0,
                        onTap: () => _selectTab(0),
                      ),
                      _BottomDestination(
                        icon: Icons.library_music_rounded,
                        label: 'Library',
                        selected: _tab == 1,
                        onTap: () => _selectTab(1),
                      ),
                      _BottomDestination(
                        icon: Icons.settings_rounded,
                        label: 'Settings',
                        selected: _tab == 2,
                        onTap: () => _selectTab(2),
                      ),
                      _BottomDestination(
                        icon: Icons.insights_rounded,
                        label: 'Usage',
                        selected: _tab == 3,
                        onTap: () => _selectTab(3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomDestination extends StatelessWidget {
  const _BottomDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 94,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? palette.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? palette.accent : palette.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: selected ? palette.accent : palette.textMuted,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
