import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../data/datasources/secure_key_datasource.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
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
    return Scaffold(
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
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
          // Scanner overlay frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryOrange, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SafeArea(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.primaryOrange.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Verify ${settingsState.wakeObjectName}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'AI photo verification is the WakeGuard target flow. This build currently scans the secure backup code to complete dismissal.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFE5E7EB)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
