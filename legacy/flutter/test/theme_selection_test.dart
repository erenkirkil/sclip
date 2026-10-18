import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sclip/main.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';

const _black = Color(0xFF000000);

void main() {
  test('trueDark palette blackens surfaces, keeps the brand green', () {
    final dark = buildSclipTheme(brightness: Brightness.dark);
    final trueDark = buildSclipTheme(
      brightness: Brightness.dark,
      trueDark: true,
    );

    expect(trueDark.colorScheme.surface, _black);
    expect(trueDark.colorScheme.surfaceContainerLowest, _black);
    // AppBar's M3 default background is colorScheme.surface. If the
    // container role equalled surface there would be no seam at all
    // between the title bar and the list underneath it.
    expect(trueDark.colorScheme.surfaceContainer, isNot(_black));
    // tonalSpot is deliberately untouched: only the surface family is
    // overridden, so the brand green and the text roles must come through
    // from the plain dark scheme verbatim.
    expect(trueDark.colorScheme.primary, dark.colorScheme.primary);
    expect(trueDark.colorScheme.onSurface, dark.colorScheme.onSurface);
  });

  test('trueDark is a no-op on the light palette', () {
    final light = buildSclipTheme();
    final lightForced = buildSclipTheme(trueDark: true);
    expect(lightForced.colorScheme.surface, light.colorScheme.surface);
  });

  testWidgets('SclipApp uses the plain dark palette when trueDark is off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(await SettingsService.load());
    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme!.colorScheme.surface, isNot(_black));
  });

  testWidgets('SclipApp uses the true-dark palette when trueDark is on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sclip.settings.trueDark': true});
    final settings = SettingsProvider(await SettingsService.load());
    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme!.colorScheme.surface, _black);
    // themeMode is untouched by the OLED axis — the user still follows
    // the system.
    expect(app.themeMode, ThemeMode.system);
  });
}
