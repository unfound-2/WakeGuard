import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../data/datasources/secure_key_datasource.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/history_cubit/dismissal_history_cubit.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../../domain/repositories/ble_repository.dart';

class ScannerScreen extends StatefulWidget {
  final int alarmId;
  const ScannerScreen({super.key, required this.alarmId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final SecureKeyDatasource _secureKeyDatasource = SecureKeyDatasource();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || capture.barcodes.isEmpty) return;
    setState(() => _isProcessing = true);

    final barcode = capture.barcodes.first;
    if (barcode.rawValue != null) {
      final isValid = await _secureKeyDatasource.verifyQRCode(
        widget.alarmId,
        barcode.rawValue!,
      );
      if (isValid) {
        if (mounted) {
          final bleState = context.read<BleConnectionBloc>().state;
          if (bleState is! BleConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Challenge code is valid, but the clock is not connected.',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
            if (mounted) setState(() => _isProcessing = false);
            return;
          }

          try {
            final repo = context.read<BleRepository>();
            final token = await _secureKeyDatasource.getDailyToken(
              widget.alarmId,
            );
            final payload = [widget.alarmId & 0xFF, ...token];
            await repo.sendCommand(bleState.device, 0x09, payload);
            if (!mounted) return;
            context.read<AlarmBloc>().add(const SetRingingAlarmEvent(null));
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Challenge verified, but dismissal could not be sent to the clock.',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
            setState(() => _isProcessing = false);
            return;
          }

          if (!mounted) return;
          final matches = context.read<AlarmBloc>().state.alarms.where(
            (a) => a.id == widget.alarmId,
          );
          context.read<DismissalHistoryCubit>().record(
            alarmId: widget.alarmId,
            method: 'QR',
            label: matches.isNotEmpty ? matches.first.label : null,
          );
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wake challenge complete. Alarm dismissed.'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Object or backup code not recognized.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _isProcessing = false);
      }
    } else if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Verify Wake Object',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Live camera preview stays full-bleed behind the glass chrome.
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Reticle: a continuous-corner frame with a soft accent glow,
          // captioned by a glass pill (matching the native ScannerView).
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: accent, width: 3),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GlassCard(
                borderRadius: 999,
                blurSigma: 18,
                tintColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Point the camera at your printed QR code',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // "Verify <object>" guidance panel, framed in a dark glass card.
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SafeArea(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  return GlassCard(
                    borderRadius: 24,
                    blurSigma: 20,
                    tintColor: Colors.black,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.center_focus_strong_rounded,
                            color: accent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Verify ${settingsState.wakeObjectName}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI photo verification is the WakeGuard target flow. '
                          'This build currently scans the secure backup code to '
                          'complete dismissal.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator(color: accent)),
            ),
        ],
      ),
    );
  }
}
