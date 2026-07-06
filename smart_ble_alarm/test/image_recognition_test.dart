import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/data/datasources/image_recognition_datasource.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';

void main() {
  group('ImageRecognitionDatasource.matchesLabel', () {
    test('matches case-insensitively and ignores surrounding whitespace', () {
      expect(
        ImageRecognitionDatasource.matchesLabel('Toothbrush', ' toothbrush '),
        isTrue,
      );
    });

    test('matches when either label contains the other', () {
      expect(
        ImageRecognitionDatasource.matchesLabel('Coffee cup', 'cup'),
        isTrue,
      );
      expect(
        ImageRecognitionDatasource.matchesLabel('cup', 'Coffee cup'),
        isTrue,
      );
    });

    test('does not match unrelated labels', () {
      expect(
        ImageRecognitionDatasource.matchesLabel('Plant', 'toothbrush'),
        isFalse,
      );
    });

    test('never matches an empty target or detection', () {
      expect(ImageRecognitionDatasource.matchesLabel('Cup', ''), isFalse);
      expect(ImageRecognitionDatasource.matchesLabel('', 'Cup'), isFalse);
    });
  });

  group('Alarm item-scan serialization', () {
    test('round-trips item fields through JSON', () {
      const alarm = Alarm(
        id: 3,
        hour: 7,
        minute: 30,
        dayMask: 0x80,
        qrRequired: true,
        itemLabel: 'Toothbrush',
        itemDescription: 'in the bathroom',
      );

      final restored = Alarm.fromJson(alarm.toJson());

      expect(restored, alarm);
      expect(restored.usesItemScan, isTrue);
    });

    test('decodes legacy alarms saved before item fields existed', () {
      final restored = Alarm.fromJson({
        'id': 1,
        'hour': 6,
        'minute': 0,
        'dayMask': 0x80,
        'qrRequired': true,
      });

      expect(restored.itemLabel, isNull);
      expect(restored.usesItemScan, isFalse);
      expect(restored.label, isNull);
      expect(restored.snoozeEnabled, isFalse);
      expect(restored.snoozeMaxCount, 0);
    });
  });

  group('Alarm label and snooze serialization', () {
    test('round-trips label and snooze fields through JSON', () {
      const alarm = Alarm(
        id: 4,
        hour: 8,
        minute: 15,
        dayMask: 0x80,
        qrRequired: true,
        label: 'Wake up',
        snoozeEnabled: true,
        snoozeMaxCount: 3,
      );

      final restored = Alarm.fromJson(alarm.toJson());

      expect(restored, alarm);
      expect(restored.label, 'Wake up');
      expect(restored.snoozeEnabled, isTrue);
      expect(restored.snoozeMaxCount, 3);
    });

    test('omits snooze count from JSON when snooze is disabled', () {
      const alarm = Alarm(
        id: 5,
        hour: 9,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
      );

      final json = alarm.toJson();

      expect(json.containsKey('snoozeEnabled'), isFalse);
      expect(json.containsKey('snoozeMaxCount'), isFalse);
      expect(json.containsKey('label'), isFalse);
    });
  });
}
