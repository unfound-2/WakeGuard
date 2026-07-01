import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../data/datasources/secure_key_datasource.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
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
      bool isValid = await _secureKeyDatasource.verifyQRCode(widget.alarmId, barcode.rawValue!);
      if (isValid) {
        // Send ALARM_DISMISS packet
        if (mounted) {
          final bleState = context.read<BleConnectionBloc>().state;
          if (bleState is BleConnected) {
            try {
              final repo = context.read<BleRepository>();
              final token = await _secureKeyDatasource.getDailyToken(widget.alarmId);
              final payload = [widget.alarmId, ...token];
              repo.sendCommand(bleState.device, 0x09, payload);
            } catch (e) {
              // Ignore or handle
            }
          }
          
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alarm Dismissed!'), backgroundColor: AppColors.success),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid QR Code'), backgroundColor: AppColors.error),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR to Dismiss', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryOrange),
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
        ],
      ),
    );
  }
}
