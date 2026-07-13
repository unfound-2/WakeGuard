import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_ble_alarm/core/notifications/notification_service.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/data/repositories/ble_repository_impl.dart';
import 'package:smart_ble_alarm/data/repositories/simulated_ble_repository_impl.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'smart_alarm_app.dart';

class SmartAlarmBootstrap extends StatefulWidget {
  const SmartAlarmBootstrap({super.key});

  @override
  State<SmartAlarmBootstrap> createState() => _SmartAlarmBootstrapState();
}

class _SmartAlarmBootstrapState extends State<SmartAlarmBootstrap> {
  late Future<_BootConfig> _bootConfig;

  @override
  void initState() {
    super.initState();
    _bootConfig = _loadBootConfig();
  }

  Future<_BootConfig> _loadBootConfig() async {
    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException(
        'WakeGuard startup timed out while loading preferences.',
      ),
    );
    final rememberedDeviceId = prefs.getString('rememberedDeviceId');

    final BleRepository bleRepository;
    if (rememberedDeviceId == 'simulated_device') {
      bleRepository = SimulatedBleRepositoryImpl();
    } else {
      bleRepository = BleRepositoryImpl();
    }

    return _BootConfig(
      prefs: prefs,
      rememberedDeviceId: rememberedDeviceId,
      bleRepository: bleRepository,
      notificationService: NotificationService(),
    );
  }

  void _retryBoot() {
    setState(() {
      _bootConfig = _loadBootConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootConfig>(
      future: _bootConfig,
      builder: (context, snapshot) {
        final config = snapshot.data;
        if (config != null) {
          return SmartAlarmApp(
            prefs: config.prefs,
            rememberedDeviceId: config.rememberedDeviceId,
            bleRepository: config.bleRepository,
            notificationService: config.notificationService,
            autoInitNotifications: true,
          );
        }

        return _StartupShell(
          status: snapshot.hasError
              ? 'Startup is taking longer than expected.'
              : null,
          onRetry: snapshot.hasError ? _retryBoot : null,
        );
      },
    );
  }
}

class _BootConfig {
  final SharedPreferences prefs;
  final String? rememberedDeviceId;
  final BleRepository bleRepository;
  final NotificationService notificationService;

  const _BootConfig({
    required this.prefs,
    required this.rememberedDeviceId,
    required this.bleRepository,
    required this.notificationService,
  });
}

class _StartupShell extends StatefulWidget {
  final String? status;
  final VoidCallback? onRetry;

  const _StartupShell({this.status, this.onRetry});

  @override
  State<_StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<_StartupShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _logoPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF2E363E),
          body: Builder(
            builder: (context) {
              final reduceMotion = MediaQuery.disableAnimationsOf(context);
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedWakeGuardMark(
                      animation: _logoPulse,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 108,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Color(0x1FFFFFFF),
                        color: AppColors.primaryOrange,
                      ),
                    ),
                    if (widget.status != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        widget.status!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: widget.onRetry,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryOrange,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimatedWakeGuardMark extends StatelessWidget {
  final Animation<double> animation;
  final bool reduceMotion;

  const _AnimatedWakeGuardMark({
    required this.animation,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: 164,
      child: CustomPaint(
        painter: _WakeGuardMarkPainter(progress: reduceMotion ? 0.62 : 0),
      ),
    );

    if (reduceMotion) return mark;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => SizedBox.square(
          dimension: 164,
          child: CustomPaint(
            painter: _WakeGuardMarkPainter(progress: animation.value),
          ),
        ),
      ),
    );
  }
}

class _WakeGuardMarkPainter extends CustomPainter {
  final double progress;

  const _WakeGuardMarkPainter({required this.progress});

  static const Color _ember = Color(0xFFFF6A00);
  static const Color _emberBright = Color(0xFFFFA51F);
  static const Color _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 120;
    Offset p(double x, double y) => Offset(x * scale, y * scale);

    final sunCenter = p(60, 64);
    final sunRadius = 28 * scale;
    final emberPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7.2 * scale
      ..color = _ember;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 11 * scale
      ..color = _ember.withValues(alpha: 0.13);

    final arcRect = Rect.fromCircle(center: sunCenter, radius: sunRadius);
    canvas.drawArc(arcRect, math.pi, math.pi, false, glowPaint);
    canvas.drawArc(arcRect, math.pi, math.pi, false, emberPaint);

    final rays = <({Offset start, Offset end, double phase})>[
      (start: p(60, 18), end: p(60, 33), phase: 0.00),
      (start: p(30, 31), end: p(41, 42), phase: 0.16),
      (start: p(18, 59), end: p(32, 62), phase: 0.32),
      (start: p(90, 31), end: p(79, 42), phase: 0.48),
      (start: p(102, 59), end: p(88, 62), phase: 0.64),
    ];

    for (final ray in rays) {
      final pulse = _wave(progress + ray.phase);
      final alpha = 0.22 + (pulse * 0.78);
      final color = Color.lerp(_ember, _emberBright, pulse)!;
      final rayPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 6 * scale
        ..color = color.withValues(alpha: alpha);
      final rayGlowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 10 * scale
        ..color = color.withValues(alpha: 0.05 + (pulse * 0.18));

      canvas
        ..drawLine(ray.start, ray.end, rayGlowPaint)
        ..drawLine(ray.start, ray.end, rayPaint);
    }

    final wPath = Path()
      ..moveTo(p(22, 77).dx, p(22, 77).dy)
      ..lineTo(p(38, 94).dx, p(38, 94).dy)
      ..lineTo(p(60, 72).dx, p(60, 72).dy)
      ..lineTo(p(82, 94).dx, p(82, 94).dy)
      ..lineTo(p(98, 77).dx, p(98, 77).dy);

    final wGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 12 * scale
      ..color = _white.withValues(alpha: 0.08);
    final wPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 7.5 * scale
      ..color = _white;

    canvas
      ..drawPath(wPath, wGlowPaint)
      ..drawPath(wPath, wPaint);
  }

  double _wave(double value) {
    final normalized = value - value.floorToDouble();
    return 0.5 + (0.5 * math.sin((normalized * math.pi * 2) - math.pi / 2));
  }

  @override
  bool shouldRepaint(covariant _WakeGuardMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
