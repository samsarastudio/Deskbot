import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared cyan-ice NOVA language (phone + 1.47" LCD).
class NovaColors {
  static const bg = Color(0xFF070B12);
  static const bgMid = Color(0xFF0E1622);
  static const panel = Color(0xCC121A26);
  static const panelSolid = Color(0xFF151D2A);
  static const ink = Color(0xFFF2F7FC);
  static const muted = Color(0xFF8FA3B8);
  static const line = Color(0xFF2A3A4D);
  static const accent = Color(0xFF6EE7FF);
  static const accentSoft = Color(0x336EE7FF);
  static const good = Color(0xFF7DFFA6);
  static const bad = Color(0xFFFF7D8A);
  static const face = Color(0xFFD6F7FF);
  static const lcd = Color(0xFF071018);
  static const gold = Color(0xFFFFD27A);
  static const heart = Color(0xFFFF6B9A);
  static const warn = Color(0xFFFFD27A);
}

class NovaTheme {
  static TextTheme _textTheme() {
    // Sora = geometric display (premium, not toy). Figtree = soft modern body.
    final display = GoogleFonts.sora(
      color: NovaColors.ink,
      fontWeight: FontWeight.w600,
    );
    final body = GoogleFonts.figtree(
      color: NovaColors.ink,
      fontWeight: FontWeight.w500,
    );
    return TextTheme(
      displayLarge: display.copyWith(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.02,
      ),
      displayMedium: display.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.08,
      ),
      displaySmall: display.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.12,
      ),
      headlineMedium: display.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
      ),
      titleLarge: body.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25),
      titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
      bodyLarge: body.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.55,
        color: NovaColors.ink,
        letterSpacing: 0.1,
      ),
      bodyMedium: body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.5,
        color: NovaColors.muted,
        letterSpacing: 0.15,
      ),
      labelLarge: body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
    );
  }

  static ThemeData dark() {
    final text = _textTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NovaColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: NovaColors.accent,
        secondary: NovaColors.gold,
        surface: NovaColors.panelSolid,
        error: NovaColors.bad,
        onPrimary: NovaColors.bg,
        onSurface: NovaColors.ink,
      ),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: NovaColors.ink,
        titleTextStyle: text.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NovaColors.accent,
          foregroundColor: NovaColors.bg,
          elevation: 0,
          shadowColor: NovaColors.accent.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          textStyle: text.labelLarge?.copyWith(color: NovaColors.bg),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return 0;
            return 8;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NovaColors.ink,
          side: BorderSide(color: NovaColors.line.withValues(alpha: 0.9)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NovaColors.panelSolid,
        hintStyle: text.bodyLarge?.copyWith(color: NovaColors.muted.withValues(alpha: 0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: NovaColors.accent, width: 1.4),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

enum NovaMood { happy, curious, thinking, love, sleepy, worried, focused, surprised }
