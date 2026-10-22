import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';
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
  static const double _destinationWidth = 94;

  int _tab = 0;
  int _searchFocusTick = 0;
  int _homeResetTick = 0;
  final ScrollController _navScrollController = ScrollController();

  @override
  void dispose() {
    _navScrollController.dispose();
    super.dispose();
  }

  /// The bottom row starts with Search centred and Library/Settings/Usage
  /// running off to its right. Selecting (or swiping) scrolls the row left
  /// until the chosen destination is the centred one.
  void _centreDestination(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_navScrollController.hasClients) return;
      final target = (index * _destinationWidth)
          .clamp(0.0, _navScrollController.position.maxScrollExtent);
      _navScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _selectTab(int index) {
    if (index == 0 && _tab == 0) {
      // A second tap on Search means “put me in the search box”, with the
      // keyboard open and the existing text selected for replacement.
      setState(() => _searchFocusTick++);
      _centreDestination(0);
      return;
    }
    setState(() => _tab = index);
    _centreDestination(index);
  }

  void _goHome() {
    setState(() {
      _tab = 0;
      _homeResetTick++;
    });
    _centreDestination(0);
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
    // One UI one-hand mode gives the bottom navigation taller, easier
    // thumb targets. Turning it off restores the compact bar.
    final oneHand = context.watch<AppSettingsService>().oneHandModeEnabled;
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
                height: oneHand ? 74 : 64,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Centre the first destination (Search) by padding
                    // both ends by half the spare width; the remaining
                    // destinations extend to the right and the row scrolls
                    // left to bring each one to the centre.
                    final sidePadding =
                        (constraints.maxWidth - _destinationWidth) / 2;
                    return SingleChildScrollView(
                      controller: _navScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: sidePadding),
                      child: Row(
                        children: <Widget>[
                          _BottomDestination(
                            icon: Icons.search_rounded,
                            label: 'Search',
                            selected: _tab == 0,
                            oneHand: oneHand,
                            onTap: () => _selectTab(0),
                          ),
                          _BottomDestination(
                            icon: Icons.library_music_rounded,
                            label: 'Library',
                            selected: _tab == 1,
                            oneHand: oneHand,
                            onTap: () => _selectTab(1),
                          ),
                          _BottomDestination(
                            icon: Icons.settings_rounded,
                            label: 'Settings',
                            selected: _tab == 2,
                            oneHand: oneHand,
                            onTap: () => _selectTab(2),
                          ),
                          _BottomDestination(
                            icon: Icons.insights_rounded,
                            label: 'Usage',
                            selected: _tab == 3,
                            oneHand: oneHand,
                            onTap: () => _selectTab(3),
                          ),
                        ],
                      ),
                    );
                  },
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
    this.oneHand = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool oneHand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: _MainShellState._destinationWidth,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: oneHand ? 6 : 4,
              ),
              decoration: BoxDecoration(
                gradient: selected
                    ? LinearGradient(
                        colors: <Color>[
                          palette.accent.withValues(alpha: 0.30),
                          palette.mint.withValues(alpha: 0.22),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: selected
                    ? Border.all(
                        color: palette.accent.withValues(alpha: 0.35),
                        width: 0.7,
                      )
                    : null,
              ),
              child: Icon(
                icon,
                size: oneHand ? 24 : 22,
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
