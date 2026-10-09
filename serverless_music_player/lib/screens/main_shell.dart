import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'usage_dashboard_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: const <Widget>[
            HomeScreen(),
            LibraryScreen(),
            UsageDashboardScreen(),
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
              NavigationBar(
                height: 64,
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                    icon: Icon(Icons.search_rounded),
                    selectedIcon: Icon(Icons.search_rounded),
                    label: 'Discover',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.insights_outlined),
                    selectedIcon: Icon(Icons.insights_rounded),
                    label: 'Usage',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
