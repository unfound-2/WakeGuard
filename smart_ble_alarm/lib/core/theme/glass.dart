import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_background.dart';
import 'app_colors.dart';

/// Theme-aware tokens for translucent "glass" surfaces. Attached to [ThemeData]
/// via [ThemeExtension] so every screen reads the same values in both light and
/// dark mode instead of hand-rolling blur/tint/stroke constants.
class GlassTheme extends ThemeExtension<GlassTheme> {
  final List<Color> backgroundGradient;
  final Color tint; // base colour of a glass fill
  final Color elevated; // raised inner surfaces (tiles, secondary buttons)
  final Color stroke; // hairline border on glass
  final double blurSigma;
  final double fillOpacity;
  final Brightness brightness;

  const GlassTheme({
    required this.backgroundGradient,
    required this.tint,
    required this.elevated,
    required this.stroke,
    required this.blurSigma,
    required this.fillOpacity,
    required this.brightness,
  });

  static const GlassTheme dark = GlassTheme(
    backgroundGradient: [
      AppColors.backgroundGradientTop,
      AppColors.backgroundGradientMid,
      AppColors.backgroundGradientBottom,
    ],
    tint: AppColors.surface,
    elevated: AppColors.elevatedSurface,
    stroke: AppColors.glassStrokeDark,
    blurSigma: 18,
    fillOpacity: 0.52,
    brightness: Brightness.dark,
  );

  static const GlassTheme light = GlassTheme(
    backgroundGradient: [
      AppColors.lightBackgroundGradientTop,
      AppColors.lightBackgroundGradientMid,
      AppColors.lightBackgroundGradientBottom,
    ],
    tint: Color(0xFFFFFFFF),
    elevated: AppColors.lightElevatedSurface,
    stroke: AppColors.glassStrokeLight,
    blurSigma: 18,
    fillOpacity: 0.78,
    brightness: Brightness.light,
  );

  static GlassTheme of(BuildContext context) =>
      Theme.of(context).extension<GlassTheme>() ?? dark;

  @override
  GlassTheme copyWith({
    List<Color>? backgroundGradient,
    Color? tint,
    Color? elevated,
    Color? stroke,
    double? blurSigma,
    double? fillOpacity,
    Brightness? brightness,
  }) {
    return GlassTheme(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      tint: tint ?? this.tint,
      elevated: elevated ?? this.elevated,
      stroke: stroke ?? this.stroke,
      blurSigma: blurSigma ?? this.blurSigma,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    final stops = backgroundGradient.length == other.backgroundGradient.length
        ? List<Color>.generate(
            backgroundGradient.length,
            (i) => Color.lerp(
              backgroundGradient[i],
              other.backgroundGradient[i],
              t,
            )!,
          )
        : (t < 0.5 ? backgroundGradient : other.backgroundGradient);
    return GlassTheme(
      backgroundGradient: stops,
      tint: Color.lerp(tint, other.tint, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
      fillOpacity: lerpDouble(fillOpacity, other.fillOpacity, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

/// Full-bleed background: the diagonal charcoal-to-slate wash from the native
/// WakeGuard app plus two soft accent glows for ambient, liquid light. Cheap to
/// paint (no backdrop blur) so it can sit behind every screen.
class GlassBackground extends StatelessWidget {
  final Widget child;

  /// When false the accent glows are hidden (e.g. behind a camera preview).
  final bool showGlow;

  const GlassBackground({super.key, required this.child, this.showGlow = true});

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // The chosen background style is mirrored in a global notifier by SettingsBloc
    // so switching it updates every screen live. `minimal` keeps the original
    // static wash + soft glows; the flowy styles paint an animated layer instead.
    return ValueListenableBuilder<AppBackgroundStyle>(
      valueListenable: appBackgroundStyle,
      builder: (context, style, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: glass.backgroundGradient,
            ),
          ),
          child: Stack(
            children: [
              if (showGlow && style == AppBackgroundStyle.minimal) ...[
                _Glow(
                  alignment: const Alignment(-1.1, -0.95),
                  color: accent.withValues(alpha: 0.10),
                  size: 360,
                ),
                _Glow(
                  alignment: const Alignment(1.2, 0.65),
                  color: accent.withValues(alpha: 0.06),
                  size: 320,
                ),
              ],
              if (showGlow && style != AppBackgroundStyle.minimal)
                Positioned.fill(
                  child: AnimatedAppBackground(
                    style: style,
                    accent: accent,
                    animate: !reduceMotion,
                  ),
                ),
              Positioned.fill(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double size;
  const _Glow({
    required this.alignment,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The canonical translucent surface: a blurred, tinted, hairline-bordered
/// panel with a subtle top specular highlight. Use for cards, list containers,
/// status chips — anywhere that previously hand-built a BackdropFilter.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double borderWidth;
  final Color? tintColor; // overrides the neutral glass tint (e.g. accent wash)
  final double? blurSigma;
  final List<BoxShadow>? shadows;

  /// When false, the card skips the live `BackdropFilter` and paints a solid
  /// (slightly more opaque) tinted fill instead. Use this for rows inside a
  /// scrolling list: a real backdrop blur re-samples the moving content behind
  /// every visible row on every frame, which is the main cause of scroll jank
  /// and heat. Static/hero cards can keep the frosted blur (the default).
  final bool blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 28,
    this.onTap,
    this.borderColor,
    this.borderWidth = 1,
    this.tintColor,
    this.blurSigma,
    this.shadows,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final baseTint = tintColor ?? glass.tint;
    final baseOpacity = tintColor != null
        ? (glass.brightness == Brightness.dark ? 0.20 : 0.16)
        : glass.fillOpacity;
    // Without a live blur the fill must carry the surface on its own, so nudge
    // it more opaque to stay legible over a busy background.
    final fill = baseTint.withValues(
      alpha: blur ? baseOpacity : (baseOpacity + 0.14).clamp(0.0, 1.0),
    );
    final highlight = glass.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.55);

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(highlight, fill), fill],
        ),
        border: Border.all(
          color: borderColor ?? glass.stroke,
          width: borderWidth,
        ),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    Widget content = ClipRRect(
      borderRadius: radius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurSigma ?? glass.blurSigma,
                sigmaY: blurSigma ?? glass.blurSigma,
              ),
              child: decorated,
            )
          : decorated,
    );

    if (onTap != null) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }

    if (shadows != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
        child: content,
      );
    }

    return content;
  }
}
