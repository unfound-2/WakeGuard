import 'package:flutter/material.dart';

/// Central colour tokens for the app's "Liquid Glass" design language.
///
/// The palette is intentionally vibrant but restrained: deep, slightly-blue
/// darks and soft, cool lights let translucent glass surfaces and accent glows
/// read clearly while keeping text at accessible contrast.
class AppColors {
  AppColors._();

  // ---- Dark theme base ----------------------------------------------------
  static const Color background = Color(
    0xFF0A0B12,
  ); // near-black, blue undertone
  static const Color backgroundGradientTop = Color(0xFF14161F);
  static const Color backgroundGradientBottom = Color(0xFF05060B);
  static const Color surface = Color(0xFF161824); // opaque glass fallback
  static const Color textPrimary = Color(0xFFF3F4FA);
  static const Color textSecondary = Color(0xFF9AA2B6);
  static const Color glassStrokeDark = Color(0x24FFFFFF); // white @ ~14%

  // ---- Light theme base ---------------------------------------------------
  static const Color lightBackground = Color(0xFFEEF0F7);
  static const Color lightBackgroundGradientTop = Color(0xFFF8F9FD);
  static const Color lightBackgroundGradientBottom = Color(0xFFE6E9F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF11131C);
  static const Color textSecondaryLight = Color(0xFF5A6274);
  static const Color glassStrokeLight = Color(0x14101320); // ink @ ~8%

  // ---- Accent presets -----------------------------------------------------
  // Kept string-compatible with previously stored preferences.
  static const Color primaryOrange = Color(0xFFFF6B35); // default "Neon Orange"
  static const Color neonBlue = Color(0xFF6C63FF);

  // ---- Feedback -----------------------------------------------------------
  static const Color error = Color(0xFFFF453A);
  static const Color success = Color(0xFF32D74B);
  static const Color warning = Color(0xFFFFB020);

  /// Resolves a stored accent preference string to its seed colour.
  static Color accentFromString(String name) {
    switch (name) {
      case 'Cyber Cyan':
        return const Color(0xFF06B6D4);
      case 'Matrix Green':
        return const Color(0xFF10B981);
      case 'Neon Blue':
        return neonBlue;
      case 'Neon Orange':
      default:
        return primaryOrange;
    }
  }

  /// A two-stop gradient for the accent, used on primary buttons and glows to
  /// give the interface a sense of depth and "liquid" light.
  static List<Color> accentGradient(String name) {
    switch (name) {
      case 'Cyber Cyan':
        return const [Color(0xFF22D3EE), Color(0xFF0891B2)];
      case 'Matrix Green':
        return const [Color(0xFF34D399), Color(0xFF059669)];
      case 'Neon Blue':
        return const [Color(0xFF8B87FF), Color(0xFF6C63FF)];
      case 'Neon Orange':
      default:
        return const [Color(0xFFFF8A3D), Color(0xFFFF5C6E)];
    }
  }

  /// The list of selectable accent names, in display order.
  static const List<String> accentNames = [
    'Neon Orange',
    'Cyber Cyan',
    'Matrix Green',
    'Neon Blue',
  ];
}
