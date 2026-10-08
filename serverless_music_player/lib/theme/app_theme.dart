import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF090A10);
  static const Color surface = Color(0xFF141620);
  static const Color surfaceRaised = Color(0xFF1B1E2B);
  static const Color accent = Color(0xFFB69CFF);
  static const Color mint = Color(0xFF7EE7D3);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
          primary: accent,
          secondary: mint,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: const TextStyle(color: Color(0xFF85899B)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: background,
          indicatorColor: accent.withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? accent
                  : const Color(0xFF85899B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }),
        ),
        tabBarTheme: const TabBarThemeData(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: accent,
          unselectedLabelColor: Color(0xFF85899B),
          labelStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: Colors.white12,
          thumbColor: Colors.white,
          overlayColor: accent.withValues(alpha: 0.12),
          trackHeight: 3,
        ),
      );
}
