import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Theme-aware tokens for translucent "glass" surfaces. Attached to [ThemeData]
/// via [ThemeExtension] so every screen reads the same values in both light and
/// dark mode instead of hand-rolling blur/tint/stroke constants.
class GlassTheme extends ThemeExtension<GlassTheme> {
  final List<Color> backgroundGradient;
  final Color tint; // base colour of a glass fill
  final Color stroke; // hairline border on glass
  final double blurSigma;
  final double fillOpacity;
  final Brightness brightness;

  const GlassTheme({
    required this.backgroundGradient,
    required this.tint,
    required this.stroke,
    required this.blurSigma,
    required this.fillOpacity,
    required this.brightness,
  });

  static const GlassTheme dark = GlassTheme(
    backgroundGradient: [
      AppColors.backgroundGradientTop,
      AppColors.backgroundGradientBottom,
    ],
    tint: Color(0xFFFFFFFF),
    stroke: AppColors.glassStrokeDark,
    blurSigma: 22,
    fillOpacity: 0.06,
    brightness: Brightness.dark,
  );

  static const GlassTheme light = GlassTheme(
    backgroundGradient: [
      AppColors.lightBackgroundGradientTop,
      AppColors.lightBackgroundGradientBottom,
    ],
    tint: Color(0xFFFFFFFF),
    stroke: AppColors.glassStrokeLight,
    blurSigma: 22,
    fillOpacity: 0.72,
    brightness: Brightness.light,
  );

  static GlassTheme of(BuildContext context) =>
      Theme.of(context).extension<GlassTheme>() ?? dark;

  @override
  GlassTheme copyWith({
    List<Color>? backgroundGradient,
    Color? tint,
    Color? stroke,
    double? blurSigma,
    double? fillOpacity,
    Brightness? brightness,
  }) {
    return GlassTheme(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      tint: tint ?? this.tint,
      stroke: stroke ?? this.stroke,
      blurSigma: blurSigma ?? this.blurSigma,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    return GlassTheme(
      backgroundGradient: [
        Color.lerp(
          backgroundGradient.first,
          other.backgroundGradient.first,
          t,
        )!,
        Color.lerp(backgroundGradient.last, other.backgroundGradient.last, t)!,
      ],
      tint: Color.lerp(tint, other.tint, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
      fillOpacity: lerpDouble(fillOpacity, other.fillOpacity, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

/// Full-bleed background: the theme gradient plus two soft accent glows that
/// give screens depth and a sense of ambient, liquid light. Cheap to paint
/// (no backdrop blur) so it can sit behind every screen.
class GlassBackground extends StatelessWidget {
  final Widget child;

  /// When false the accent glows are hidden (e.g. behind a camera preview).
  final bool showGlow;

  const GlassBackground({super.key, required this.child, this.showGlow = true});

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: glass.backgroundGradient,
        ),
      ),
      child: Stack(
        children: [
          if (showGlow) ...[
            _Glow(
              alignment: const Alignment(-1.1, -0.95),
              color: accent.withValues(alpha: 0.22),
              size: 340,
            ),
            _Glow(
              alignment: const Alignment(1.2, 0.65),
              color: accent.withValues(alpha: 0.14),
              size: 300,
            ),
          ],
          Positioned.fill(child: child),
        ],
      ),
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

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 26,
    this.onTap,
    this.borderColor,
    this.borderWidth = 1,
    this.tintColor,
    this.blurSigma,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final baseTint = tintColor ?? glass.tint;
    final fill = tintColor != null
        ? baseTint.withValues(
            alpha: glass.brightness == Brightness.dark ? 0.20 : 0.16,
          )
        : baseTint.withValues(alpha: glass.fillOpacity);
    final highlight = glass.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.55);

    Widget content = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma ?? glass.blurSigma,
          sigmaY: blurSigma ?? glass.blurSigma,
        ),
        child: DecoratedBox(
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
        ),
      ),
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
