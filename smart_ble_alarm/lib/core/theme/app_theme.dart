import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'glass.dart';

/// Builds the app's Material 3 themes for the "Liquid Glass" design language.
///
/// Both light and dark variants share the same accent and component shapes so
/// the interface feels cohesive when the user switches modes. Screens read the
/// translucency tokens from the attached [GlassTheme] extension.
class AppTheme {
  AppTheme._();

  static ThemeData getTheme({
    Color accentColor = AppColors.primaryOrange,
    bool isDarkMode = true,
  }) {
    final bg = isDarkMode ? AppColors.background : AppColors.lightBackground;
    final surface = isDarkMode ? AppColors.surface : AppColors.lightSurface;
    final textPrimary = isDarkMode
        ? AppColors.textPrimary
        : AppColors.textPrimaryLight;
    final textSecondary = isDarkMode
        ? AppColors.textSecondary
        : AppColors.textSecondaryLight;
    final stroke = isDarkMode
        ? AppColors.glassStrokeDark
        : AppColors.glassStrokeLight;
    final brightness = isDarkMode ? Brightness.dark : Brightness.light;

    // Pick black/white for text drawn on the accent based on its luminance, so
    // a light accent preset doesn't leave white-on-light text unreadable.
    final onAccent =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accentColor,
      onPrimary: onAccent,
      primaryContainer: accentColor.withValues(alpha: isDarkMode ? 0.22 : 0.14),
      onPrimaryContainer: accentColor,
      secondary: accentColor,
      onSecondary: onAccent,
      error: AppColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: stroke,
      outlineVariant: stroke,
    );

    final baseText = GoogleFonts.interTextTheme(
      (isDarkMode ? ThemeData.dark() : ThemeData.light()).textTheme,
    ).apply(bodyColor: textPrimary, displayColor: textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: stroke,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseText.copyWith(
        displayLarge: baseText.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        bodyMedium: baseText.bodyMedium?.copyWith(color: textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface.withValues(alpha: isDarkMode ? 0.6 : 0.8),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDarkMode ? const Color(0xFF1B1D2A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.inter(color: textSecondary, fontSize: 15),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDarkMode ? const Color(0xFF1B1D2A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: accentColor.withValues(
          alpha: isDarkMode ? 0.16 : 0.12,
        ),
        side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDarkMode
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        hintStyle: TextStyle(color: textSecondary),
        labelStyle: TextStyle(color: textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: stroke),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDarkMode ? const Color(0xFFB4BAC8) : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentColor;
          return isDarkMode
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.12);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      extensions: <ThemeExtension<dynamic>>[
        isDarkMode ? GlassTheme.dark : GlassTheme.light,
      ],
    );
  }
}
