import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/core/theme/app_theme.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';

/// Regression guard for the accessibility text-overflow bug: with iOS "Bold
/// Text" and/or large Dynamic Type, the shared buttons must GROW and wrap their
/// label rather than clip a second line. We render them inside a realistically
/// narrow column at an exaggerated text scale + bold and assert that no
/// RenderFlex/overflow exception is thrown during layout.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.getTheme(isDarkMode: false),
    home: Scaffold(
      // A deliberately tight width so a long label would overflow a fixed box.
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );

  Widget scaled(Widget child) => MediaQuery(
    // 2x text and bold text: the two things iOS accessibility can throw at us.
    data: const MediaQueryData(
      textScaler: TextScaler.linear(2.0),
      boldText: true,
    ),
    child: child,
  );

  testWidgets('WakePrimaryButton does not overflow at 2x bold text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        scaled(
          WakePrimaryButton(
            label: 'Sync Time, Alarms & Settings',
            icon: Icons.sync_rounded,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // It must have grown past the base 54pt to fit the wrapped label.
    expect(
      tester.getSize(find.byType(WakePrimaryButton)).height,
      greaterThan(54),
    );
  });

  testWidgets('WakeSecondaryButton does not overflow at 2x bold text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        scaled(
          WakeSecondaryButton(
            label: 'Reconnect Device',
            icon: Icons.bluetooth_searching_rounded,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('WakePrimaryButton is still exactly 54pt at normal text', (
    tester,
  ) async {
    // The fix must be invisible to normal users: base height unchanged.
    await tester.pumpWidget(
      host(
        WakePrimaryButton(
          label: 'Sync Now',
          icon: Icons.sync_rounded,
          onPressed: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(WakePrimaryButton)).height, 54);
  });
}
