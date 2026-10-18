import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsProvider.trueDark', () {
    test('write-through persists and notifies exactly once', () async {
      final provider = SettingsProvider(await SettingsService.load());
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.trueDark, isFalse);
      await provider.setTrueDark(true);
      expect(provider.trueDark, isTrue);
      expect(notifications, 1);

      // Early exit on an unchanged value. MaterialApp's theme rebuild hangs
      // off this listener; a re-notify per no-op setter call would rebuild
      // the whole app for nothing.
      await provider.setTrueDark(true);
      expect(notifications, 1);

      expect((await SettingsService.load()).trueDark, isTrue);
    });

    test('resetAll restores the default', () async {
      SharedPreferences.setMockInitialValues({'sclip.settings.trueDark': true});
      final provider = SettingsProvider(await SettingsService.load());
      expect(provider.trueDark, isTrue);

      await provider.resetAll();
      expect(provider.trueDark, isFalse);
    });

    test('themeMode is orthogonal — trueDark does not touch it', () async {
      final provider = SettingsProvider(await SettingsService.load());
      await provider.setThemeMode(ThemeMode.system);
      await provider.setTrueDark(true);

      // K-05: the whole point of the two-axis design is that "follow the
      // system" survives an OLED preference. A single 4-value enum would
      // have pinned this to ThemeMode.dark.
      expect(provider.themeMode, ThemeMode.system);
      expect((await SettingsService.load()).themeMode, ThemeMode.system);
    });
  });
}
