import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

class SecureKeyDatasource {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _keyPrefix = 'alarm_key_';

  Future<List<int>> _getOrGenerateKey(int alarmId) async {
    String keyName = '$_keyPrefix$alarmId';
    String? base64Key = await _storage.read(key: keyName);
    if (base64Key != null) {
      return base64Decode(base64Key);
    }
    
    // Generate new 128-bit (16 byte) random key
    final random = Random.secure();
    final keyBytes = List<int>.generate(16, (_) => random.nextInt(256));
    await _storage.write(key: keyName, value: base64Encode(keyBytes));
    return keyBytes;
  }
  
  /// Generates the static 8-byte token for a given alarm
  Future<List<int>> getDailyToken(int alarmId) async {
    final key = await _getOrGenerateKey(alarmId);
    
    // Payload = AlarmID (static so printed QR code is permanently valid)
    List<int> payload = [alarmId];
    
    var hmac = Hmac(sha256, key);
    var digest = hmac.convert(payload);
    
    // Return first 8 bytes of the hash as the token
    return digest.bytes.sublist(0, 8);
  }
  
  /// Generates the QR code string for the alarm
  Future<String> getQRCodeData(int alarmId) async {
    final token = await getDailyToken(alarmId);
    return base64Encode(token);
  }

  /// Verifies scanned QR code string
  Future<bool> verifyQRCode(int alarmId, String scannedData) async {
    final expectedToken = await getDailyToken(alarmId);
    final expectedBase64 = base64Encode(expectedToken);
    return scannedData == expectedBase64;
  }
}
