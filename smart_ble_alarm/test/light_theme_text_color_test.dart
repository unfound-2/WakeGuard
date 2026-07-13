import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/core/theme/app_theme.dart';

/// Regression guard for the "white text in light mode" report: the light theme
/// must resolve DARK foreground colours. If a future change points the light
/// theme at a white/near-white text token, these assertions fail before it
/// ships. (The dark theme is deliberately the inverse and is not asserted here.)
void main() {
  test('light theme resolves dark (not white) foreground colours', () {
    final t = AppTheme.getTheme(isDarkMode: false);

    expect(t.brightness, Brightness.light);

    // computeLuminance() ~1.0 is white, ~0.0 is black. Primary/secondary text
    // and the default body colour must all read as clearly dark.
    expect(
      t.colorScheme.onSurface.computeLuminance(),
      lessThan(0.35),
      reason: 'onSurface should be dark slate in light mode',
    );
    expect(
      t.colorScheme.onSurfaceVariant.computeLuminance(),
      lessThan(0.5),
      reason: 'secondary text should still read dark on a light surface',
    );
    expect(t.textTheme.bodyLarge!.color!.computeLuminance(), lessThan(0.35));
    expect(t.textTheme.titleLarge!.color!.computeLuminance(), lessThan(0.35));
  });

  testWidgets('default Text under the light theme is dark', (tester) async {
    late Color resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getTheme(isDarkMode: false),
        darkTheme: AppTheme.getTheme(isDarkMode: true),
        themeMode: ThemeMode.light,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              resolved =
                  DefaultTextStyle.of(context).style.color ??
                  const Color(0xFFFFFFFF);
              return const Text('sample');
            },
          ),
        ),
      ),
    );
    expect(
      resolved.computeLuminance(),
      lessThan(0.6),
      reason: 'ambient text colour in a light Scaffold must not be white',
    );
  });
}
