import 'package:flutter/material.dart';

/// Central colour tokens for the WakeGuard "Liquid Glass" design language.
///
/// The palette mirrors the native WakeGuard reference app: warm charcoal
/// darks, slate lights, and a burnt-ember accent, with hairline strokes and
/// translucent surfaces doing the visual work instead of saturated neon.
class AppColors {
  AppColors._();

  // ---- Dark theme base ----------------------------------------------------
  static const Color background = Color(0xFF0D1115); // warm charcoal
  static const Color backgroundGradientTop = Color(0xFF0D1115);
  static const Color backgroundGradientMid = Color(0xFF1D242A); // slate wash
  static const Color backgroundGradientBottom = Color(0xFF0D1115);
  static const Color surface = Color(0xFF182026);
  static const Color elevatedSurface = Color(0xFF222C33);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textBody = Color(0xFFD8DEE3);
  static const Color textSecondary = Color(0xFFA7B0B8);
  static const Color glassStrokeDark = Color(0x1AFFFFFF); // white @ 10%

  // ---- Light theme base ---------------------------------------------------
  static const Color lightBackground = Color(0xFFF4F6F8);
  static const Color lightBackgroundGradientTop = Color(0xFFF4F6F8);
  static const Color lightBackgroundGradientMid = Color(0xFFE7EAEE);
  static const Color lightBackgroundGradientBottom = Color(0xFFF4F6F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightElevatedSurface = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF333F48); // deep slate
  static const Color textBodyLight = Color(0xFF4B5963);
  static const Color textSecondaryLight = Color(0xFF6F7B84);
  static const Color glassStrokeLight = Color(0x14000000); // ink @ 8%

  // ---- Accent presets -----------------------------------------------------
  /// Default accent: the native WakeGuard burnt ember.
  static const Color primaryOrange = Color(0xFFBF5700);
  static const Color neonBlue = Color(0xFF5E5CE6);

  // ---- Feedback -----------------------------------------------------------
  static const Color error = Color(0xFFFF453A);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFB020);

  /// Resolves a stored accent preference string to its seed colour.
  /// Legacy names (pre-rebrand) keep resolving so saved prefs never break.
  static Color accentFromString(String name) {
    switch (name) {
      case 'Sky':
      case 'Cyber Cyan': // legacy
        return const Color(0xFF0A84FF);
      case 'Mint':
      case 'Matrix Green': // legacy
        return const Color(0xFF30D158);
      case 'Indigo':
      case 'Neon Blue': // legacy
        return neonBlue;
      case 'Ember':
      case 'Neon Orange': // legacy
      default:
        return primaryOrange;
    }
  }

  /// Maps any stored accent name (including legacy ones) onto the canonical
  /// display name so selection checkmarks stay correct after the rebrand.
  static String canonicalAccentName(String name) {
    switch (name) {
      case 'Sky':
      case 'Cyber Cyan':
        return 'Sky';
      case 'Mint':
      case 'Matrix Green':
        return 'Mint';
      case 'Indigo':
      case 'Neon Blue':
        return 'Indigo';
      default:
        return 'Ember';
    }
  }

  /// A restrained two-stop gradient for the accent, used on primary buttons
  /// and glows for a sense of depth without neon saturation.
  static List<Color> accentGradient(String name) {
    switch (canonicalAccentName(name)) {
      case 'Sky':
        return const [Color(0xFF3B9BFF), Color(0xFF0A84FF)];
      case 'Mint':
        return const [Color(0xFF4FDD75), Color(0xFF30D158)];
      case 'Indigo':
        return const [Color(0xFF7A78F0), Color(0xFF5E5CE6)];
      case 'Ember':
      default:
        return const [Color(0xFFD96C1A), Color(0xFFBF5700)];
    }
  }

  /// The list of selectable accent names, in display order.
  static const List<String> accentNames = ['Ember', 'Sky', 'Mint', 'Indigo'];
}
