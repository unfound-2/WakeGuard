import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

class SecureKeyDatasource {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // A single app-wide dismissal key. Every alarm shares ONE backup code, so the
  // key — and the 8-byte token derived from it — is independent of alarm id: one
  // printed QR dismisses any protected alarm. The `alarmId` parameters below are
  // kept purely for call-site compatibility (scanner/item-scan/sync all still
  // pass an id); they no longer select the key.
  static const String _globalKeyName = 'alarm_key_global';

  // Fixed, domain-separated HMAC payload so the shared token is stable for the
  // life of the key and identical across alarms ('W','G').
  static const List<int> _tokenPayload = <int>[0x57, 0x47];

  Future<List<int>> _getOrGenerateKey() async {
    final String? base64Key = await _storage.read(key: _globalKeyName);
    if (base64Key != null) {
      return base64Decode(base64Key);
    }

    // Generate new 128-bit (16 byte) random key
    final random = Random.secure();
    final keyBytes = List<int>.generate(16, (_) => random.nextInt(256));
    await _storage.write(key: _globalKeyName, value: base64Encode(keyBytes));
    return keyBytes;
  }

  /// No-op, retained for call-site compatibility. With a single app-wide backup
  /// code, deleting or rotating a key would invalidate the shared printed code
  /// for EVERY alarm, so alarm add/delete must never touch it.
  Future<void> deleteKey(int alarmId) async {}

  /// The static 8-byte dismissal token. Independent of [alarmId] — the one code
  /// works for all alarms — so the token pushed to each clock slot (0x07) and
  /// sent on dismissal (0x09) is identical, and any printed code dismisses any
  /// protected alarm.
  Future<List<int>> getDailyToken(int alarmId) async {
    final key = await _getOrGenerateKey();

    var hmac = Hmac(sha256, key);
    var digest = hmac.convert(_tokenPayload);

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
    try {
      final scannedToken = base64Decode(scannedData.trim());
      return _constantTimeEquals(scannedToken, expectedToken);
    } catch (_) {
      return false;
    }
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final maxLength = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < maxLength; i++) {
      final aByte = i < a.length ? a[i] : 0;
      final bByte = i < b.length ? b[i] : 0;
      diff |= aByte ^ bByte;
    }

    return diff == 0;
  }
}
