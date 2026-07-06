import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/datasources/secure_key_datasource.dart';

class PrintQrCodeUseCase {
  final SecureKeyDatasource secureKeyDatasource;

  PrintQrCodeUseCase({required this.secureKeyDatasource});

  Future<void> execute(int alarmId) async {
    final String qrData = await secureKeyDatasource.getQRCodeData(alarmId);
    if (qrData.isEmpty) {
      throw StateError('No QR key is available for alarm $alarmId.');
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
                  'Smart Alarm Key',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  'Alarm Identifier: $alarmId',
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
                  'Scan to dismiss alarm',
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
      name: 'Smart_Alarm_QR_$alarmId.pdf',
    );
  }
}
