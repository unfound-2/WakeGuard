import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:smart_ble_alarm/data/datasources/secure_key_datasource.dart';

class PrintQrCodeUseCase {
  final SecureKeyDatasource secureKeyDatasource;

  PrintQrCodeUseCase({required this.secureKeyDatasource});

  /// Prints the single app-wide backup code. It is not alarm-specific — one
  /// printed QR dismisses any protected alarm (see [SecureKeyDatasource]).
  Future<void> execute() async {
    final String qrData = await secureKeyDatasource.getQRCodeData(0);
    if (qrData.isEmpty) {
      throw StateError('No backup code is available.');
    }

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        // Use a generic page format suitable for Android printers or roll thermal printers
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'WakeGuard Backup Code',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  'Works for every protected alarm',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 12),
                pw.BarcodeWidget(
                  data: qrData,
                  width: 140,
                  height: 140,
                  barcode: pw.Barcode.qrCode(),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Use only if object verification is unavailable',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          );
        },
      ),
    );

    // Triggers the Android Print Manager seamlessly (previously iOS AirPrint)
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'WakeGuard_Backup_Code.pdf',
    );
  }
}
