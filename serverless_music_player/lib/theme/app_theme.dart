import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.outline,
    required this.accent,
    required this.mint,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color outline;
  final Color accent;
  final Color mint;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? outline,
    Color? accent,
    Color? mint,
  }) =>
      AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        outline: outline ?? this.outline,
        accent: accent ?? this.accent,
        mint: mint ?? this.mint,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

class AppTheme {
  static const AppPalette darkPalette = AppPalette(
    background: Color(0xFF090A10),
    surface: Color(0xFF141620),
    surfaceRaised: Color(0xFF1B1E2B),
    textPrimary: Color(0xFFF6F5FB),
    textSecondary: Color(0xFFB7B8C5),
    textMuted: Color(0xFF85899B),
    outline: Color(0x33FFFFFF),
    accent: Color(0xFFB69CFF),
    mint: Color(0xFF7EE7D3),
  );

  static const AppPalette lightPalette = AppPalette(
    // Light mode is a layered lavender/grey stage, not a white page: cards
    // sit on a tinted background, raised controls sit one shade deeper, and
    // borders/shadows separate every surface.
    background: Color(0xFFE9E7F3),
    surface: Color(0xFFFAF8FF),
    surfaceRaised: Color(0xFFDCD8EC),
    textPrimary: Color(0xFF201A33),
    textSecondary: Color(0xFF554E6E),
    textMuted: Color(0xFF7D7597),
    outline: Color(0x2E3B315E),
    accent: Color(0xFF684CC0),
    mint: Color(0xFF0E7C6B),
  );

  static ThemeData get dark => _build(darkPalette, Brightness.dark);
  static ThemeData get light => _build(lightPalette, Brightness.light);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      surface: palette.surface,
      primary: palette.accent,
      secondary: palette.mint,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      scaffoldBackgroundColor: palette.background,
      appBarTheme: AppBarTheme(
        backgroundColor:
            brightness == Brightness.light ? palette.surface : palette.background,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: brightness == Brightness.light ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: brightness == Brightness.light ? 2 : 0,
        shadowColor: Colors.black.withValues(
          alpha: brightness == Brightness.light ? 0.13 : 0.28,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceRaised.withValues(alpha: 0.65),
        selectedColor: palette.accent.withValues(alpha: 0.22),
        side: BorderSide(color: palette.outline, width: 0.7),
        labelStyle: TextStyle(color: palette.textPrimary),
      ),
      iconTheme: IconThemeData(color: palette.textSecondary),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: palette.textPrimary,
            displayColor: palette.textPrimary,
          ),
      cardColor: palette.surface,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: TextStyle(color: palette.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.background,
        indicatorColor: palette.accent.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.accent
                : palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.outline,
        thumbColor: palette.textPrimary,
        overlayColor: palette.accent.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF292B37)
            : const Color(0xFF252631),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      dividerTheme: DividerThemeData(color: palette.outline, thickness: 0.7),
    );
  }
}
