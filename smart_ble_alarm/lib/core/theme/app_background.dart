import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The app's ambient background styles. [minimal] keeps the original static
/// charcoal→slate wash + soft accent glows; the others add slow, flowy motion.
enum AppBackgroundStyle { minimal, aurora, mesh, waves }

extension AppBackgroundStyleInfo on AppBackgroundStyle {
  String get storageKey => name;
  String get label => switch (this) {
    AppBackgroundStyle.minimal => 'Minimal',
    AppBackgroundStyle.aurora => 'Aurora',
    AppBackgroundStyle.mesh => 'Mesh',
    AppBackgroundStyle.waves => 'Waves',
  };
  String get blurb => switch (this) {
    AppBackgroundStyle.minimal => 'Calm, static gradient',
    AppBackgroundStyle.aurora => 'Slow drifting light',
    AppBackgroundStyle.mesh => 'Flowing colour mesh',
    AppBackgroundStyle.waves => 'Gentle rolling waves',
  };
}

AppBackgroundStyle appBackgroundStyleFromKey(String? key) {
  for (final s in AppBackgroundStyle.values) {
    if (s.storageKey == key) return s;
  }
  return AppBackgroundStyle.minimal;
}

/// App-wide selected background, mirrored by [SettingsBloc] so any [GlassBackground]
/// updates live without threading the value through every widget (same pattern as
/// `clockSyncInProgress` / `lastClockSync`).
final ValueNotifier<AppBackgroundStyle> appBackgroundStyle =
    ValueNotifier<AppBackgroundStyle>(AppBackgroundStyle.minimal);

/// A cheap, self-animating flow layer painted OVER a base gradient (it paints only
/// translucent accent shapes, so the base shows through). Falls back to a single
/// static frame when the platform requests reduced motion. No BackdropFilter, so
/// it stays light enough to sit behind scrolling content on every screen.
class AnimatedAppBackground extends StatefulWidget {
  final AppBackgroundStyle style;
  final Color accent;

  /// When false the layer paints one static frame (used for reduced-motion and
  /// for the [minimal] style, which has no motion of its own).
  final bool animate;

  const AnimatedAppBackground({
    super.key,
    required this.style,
    required this.accent,
    this.animate = true,
  });

  @override
  State<AnimatedAppBackground> createState() => _AnimatedAppBackgroundState();
}

class _AnimatedAppBackgroundState extends State<AnimatedAppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AnimatedAppBackground old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate || old.style != widget.style) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    final shouldRun =
        widget.animate && widget.style != AppBackgroundStyle.minimal;
    if (shouldRun) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == AppBackgroundStyle.minimal) {
      return const SizedBox.expand();
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _FlowPainter(
            style: widget.style,
            accent: widget.accent,
            t: _c.value,
          ),
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  final AppBackgroundStyle style;
  final Color accent;
  final double t; // 0..1 loop phase

  _FlowPainter({required this.style, required this.accent, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case AppBackgroundStyle.aurora:
        _paintBlobs(canvas, size, _auroraBlobs);
        break;
      case AppBackgroundStyle.mesh:
        _paintBlobs(canvas, size, _meshBlobs);
        break;
      case AppBackgroundStyle.waves:
        _paintWaves(canvas, size);
        break;
      case AppBackgroundStyle.minimal:
        break;
    }
  }

  // A soft radial blob: centre drifts on a Lissajous path, painted as a radial
  // gradient that fades to transparent (so no hard edge, no blur filter needed).
  void _paintBlobs(Canvas canvas, Size size, List<_Blob> blobs) {
    final tau = 2 * math.pi * t;
    for (final b in blobs) {
      final cx = size.width * (b.x + b.ax * math.sin(tau * b.sx + b.px));
      final cy = size.height * (b.y + b.ay * math.cos(tau * b.sy + b.px * 0.5));
      final r = size.longestSide * b.r;
      final color = b.tint(accent);
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 1],
        ).createShader(rect);
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  void _paintWaves(Canvas canvas, Size size) {
    final phase = 2 * math.pi * t;
    // Three translucent bands rising from the bottom, each drifting at its own
    // speed so they interleave into a gentle rolling motion.
    final bands = [
      (yFrac: 0.72, amp: 16.0, len: 1.1, speed: 1.0, alpha: 0.16),
      (yFrac: 0.80, amp: 22.0, len: 0.8, speed: -1.4, alpha: 0.12),
      (yFrac: 0.88, amp: 14.0, len: 1.4, speed: 1.8, alpha: 0.10),
    ];
    for (final b in bands) {
      final baseY = size.height * b.yFrac;
      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, baseY);
      const step = 12.0;
      for (double x = 0; x <= size.width; x += step) {
        final y =
            baseY +
            b.amp *
                math.sin(
                  (x / size.width) * math.pi * 2 * b.len + phase * b.speed,
                );
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = accent.withValues(alpha: b.alpha));
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) =>
      old.t != t || old.style != style || old.accent != accent;

  // --- Blob presets ---------------------------------------------------------
  static final List<_Blob> _auroraBlobs = [
    _Blob(
      x: 0.20,
      y: 0.18,
      ax: 0.10,
      ay: 0.08,
      sx: 1.0,
      sy: 0.7,
      r: 0.55,
      alpha: 0.20,
      hueShift: 0,
    ),
    _Blob(
      x: 0.82,
      y: 0.30,
      ax: 0.09,
      ay: 0.10,
      sx: 0.8,
      sy: 1.1,
      r: 0.50,
      alpha: 0.14,
      hueShift: 40,
      px: 1.6,
    ),
    _Blob(
      x: 0.55,
      y: 0.85,
      ax: 0.12,
      ay: 0.07,
      sx: 1.2,
      sy: 0.9,
      r: 0.60,
      alpha: 0.12,
      hueShift: -30,
      px: 3.0,
    ),
  ];

  static final List<_Blob> _meshBlobs = [
    _Blob(
      x: 0.18,
      y: 0.22,
      ax: 0.14,
      ay: 0.12,
      sx: 1.1,
      sy: 0.9,
      r: 0.48,
      alpha: 0.22,
      hueShift: 0,
    ),
    _Blob(
      x: 0.80,
      y: 0.20,
      ax: 0.12,
      ay: 0.10,
      sx: 0.9,
      sy: 1.2,
      r: 0.44,
      alpha: 0.18,
      hueShift: 55,
      px: 1.2,
    ),
    _Blob(
      x: 0.78,
      y: 0.82,
      ax: 0.13,
      ay: 0.13,
      sx: 1.3,
      sy: 0.8,
      r: 0.50,
      alpha: 0.16,
      hueShift: 120,
      px: 2.4,
    ),
    _Blob(
      x: 0.22,
      y: 0.80,
      ax: 0.11,
      ay: 0.11,
      sx: 0.7,
      sy: 1.0,
      r: 0.46,
      alpha: 0.16,
      hueShift: -60,
      px: 3.5,
    ),
  ];
}

class _Blob {
  final double x, y; // base centre (fractions of size)
  final double ax, ay; // drift amplitude (fractions)
  final double sx, sy; // drift speed multipliers
  final double r; // radius as a fraction of the longest side
  final double alpha; // peak opacity
  final double hueShift; // degrees off the accent hue for variety
  final double px; // phase offset (x drift; y drift derives from it)

  const _Blob({
    required this.x,
    required this.y,
    required this.ax,
    required this.ay,
    required this.sx,
    required this.sy,
    required this.r,
    required this.alpha,
    required this.hueShift,
    this.px = 0,
  });

  Color tint(Color accent) {
    if (hueShift == 0) return accent.withValues(alpha: alpha);
    final hsl = HSLColor.fromColor(accent);
    final shifted = hsl
        .withHue((hsl.hue + hueShift) % 360)
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
    return shifted.withValues(alpha: alpha);
  }
}

/// A small rounded preview of a background style for the settings picker. Shows
/// the same base wash + live flow, scaled down.
class AppBackgroundPreview extends StatelessWidget {
  final AppBackgroundStyle style;
  final List<Color> baseGradient;
  final Color accent;
  final bool animate;

  const AppBackgroundPreview({
    super.key,
    required this.style,
    required this.baseGradient,
    required this.accent,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: baseGradient,
          ),
        ),
        child: AnimatedAppBackground(
          style: style,
          accent: accent,
          animate: animate,
        ),
      ),
    );
  }
}
