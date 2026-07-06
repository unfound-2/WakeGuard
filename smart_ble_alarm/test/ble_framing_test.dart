import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/data/datasources/ble_framing.dart';

void main() {
  group('BleFraming', () {
    test('encodes command frames with checksum', () {
      final frame = BleFraming.encodeFrame(0x01, [0x00, 0x00, 0x00, 0x2A]);

      expect(frame, [0x5B, 0x01, 0x04, 0x00, 0x00, 0x00, 0x2A, 0x2F, 0x5D]);
    });

    test(
      'escapes control bytes and decodes back to command length payload',
      () {
        final buffer = BleFraming.encodeFrame(0x02, [0x5B, 0x5C, 0x5D, 0x01]);

        expect(buffer.contains(BleFraming.esc), isTrue);
        expect(BleFraming.decodeFrames(buffer), [
          [0x02, 0x04, 0x5B, 0x5C, 0x5D, 0x01],
        ]);
        expect(buffer, isEmpty);
      },
    );

    test('keeps partial frames in the buffer until EOF arrives', () {
      final encoded = BleFraming.encodeFrame(0x0A, [0, 0, 0, 60]);
      final buffer = encoded.take(encoded.length - 1).toList();

      expect(BleFraming.decodeFrames(buffer), isEmpty);
      expect(buffer, isNotEmpty);

      buffer.add(encoded.last);
      expect(BleFraming.decodeFrames(buffer), [
        [0x0A, 0x04, 0, 0, 0, 60],
      ]);
      expect(buffer, isEmpty);
    });

    test('escapes a cmd byte that collides with a control byte', () {
      // 0x5C is ESC. Regression: the cmd byte used to be written raw, so the
      // decoder swallowed it as an escape introducer and silently dropped the
      // whole frame.
      final buffer = BleFraming.encodeFrame(0x5C, [0x01]);

      expect(BleFraming.decodeFrames(buffer), [
        [0x5C, 0x01, 0x01],
      ]);
      expect(buffer, isEmpty);
    });

    test('drops frames with invalid checksum', () {
      final buffer = BleFraming.encodeFrame(0x03, [0x01]);
      buffer[buffer.length - 2] ^= 0xFF;

      expect(BleFraming.decodeFrames(buffer), isEmpty);
      expect(buffer, isEmpty);
    });
  });
}
