import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/widgets/ringing_dismissal.dart';

void main() {
  group('RingingDismissal task-aware action', () {
    const noTask = Alarm(
      id: 1,
      hour: 7,
      minute: 0,
      dayMask: 0x80,
      qrRequired: false,
    );
    const qrTask = Alarm(
      id: 2,
      hour: 7,
      minute: 0,
      dayMask: 0x80,
      qrRequired: true,
    );
    const itemTask = Alarm(
      id: 3,
      hour: 7,
      minute: 0,
      dayMask: 0x80,
      qrRequired: true,
      itemLabel: 'Toothbrush',
    );

    test('no dismissal task -> "Dismiss"', () {
      expect(RingingDismissal.actionLabel(noTask), 'Dismiss');
      expect(RingingDismissal.actionIcon(noTask), Icons.alarm_off_rounded);
      expect(
        RingingDismissal.instruction(noTask).toLowerCase(),
        contains('dismiss'),
      );
    });

    test('QR task -> "Scan QR"', () {
      expect(RingingDismissal.actionLabel(qrTask), 'Scan QR');
      expect(
        RingingDismissal.actionIcon(qrTask),
        Icons.qr_code_scanner_rounded,
      );
    });

    test('item/photo task -> "Take Photo" and names the item', () {
      expect(RingingDismissal.actionLabel(itemTask), 'Take Photo');
      expect(
        RingingDismissal.actionIcon(itemTask),
        Icons.center_focus_strong_rounded,
      );
      expect(RingingDismissal.instruction(itemTask), contains('Toothbrush'));
    });
  });
}
