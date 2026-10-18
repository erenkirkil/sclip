import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';
import 'package:sclip/ui/settings_page.dart';

void main() {
  const label = 'Koyu temayı siyahlaştır (OLED)';

  testWidgets('OLED switch mirrors trueDark and greys out in light mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(await SettingsService.load());
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: settings,
          onHotkeyChange: (_) async => true,
        ),
      ),
    );

    final tile = find.widgetWithText(SwitchListTile, label);
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);

    // Toggling through the tile must write through to the provider.
    await tester.tap(tile);
    await tester.pump();
    expect(settings.trueDark, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    // Light mode never renders darkTheme, so the control would be inert.
    // It stays visible (the preference is still stored) but disabled.
    await settings.setThemeMode(ThemeMode.light);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);

    // "Follow the system" must NOT disable it — the OS can flip to dark
    // at any moment and the setting has to still be reachable.
    await settings.setThemeMode(ThemeMode.system);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
  });
}
