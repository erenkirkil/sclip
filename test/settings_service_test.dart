import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sclip/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsService', () {
    test('defaults when empty', () async {
      final s = await SettingsService.load();
      expect(s.themeMode, ThemeMode.system);
      expect(s.maxItems, 30);
      expect(s.sensitiveFilterEnabled, true);
      expect(s.autoHideOnBlur, true);
      expect(s.alwaysOnTopDefault, false);
      expect(s.pollingIntervalMs, 500);
      expect(s.clearOnStartup, false);
      expect(s.toggleHotkey, isNull);
    });

    test('persists and reads back', () async {
      final s = await SettingsService.load();
      await s.setThemeMode(ThemeMode.dark);
      await s.setMaxItems(50);
      await s.setSensitiveFilterEnabled(false);
      await s.setPollingIntervalMs(1000);

      final s2 = await SettingsService.load();
      expect(s2.themeMode, ThemeMode.dark);
      expect(s2.maxItems, 50);
      expect(s2.sensitiveFilterEnabled, false);
      expect(s2.pollingIntervalMs, 1000);
    });

    test('hotkey round-trip preserves modifiers + key', () async {
      final s = await SettingsService.load();
      final hk = HotKey(
        key: PhysicalKeyboardKey.keyK,
        modifiers: const [HotKeyModifier.meta, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );
      await s.setToggleHotkey(hk);

      final restored = (await SettingsService.load()).toggleHotkey;
      expect(restored, isNotNull);
      expect(restored!.physicalKey, PhysicalKeyboardKey.keyK);
      expect(
        restored.modifiers,
        containsAll([HotKeyModifier.meta, HotKeyModifier.alt]),
      );
    });

    test('resetAll only clears sclip.* keys, preserves foreign keys', () async {
      SharedPreferences.setMockInitialValues({
        'other_plugin.something': 'preserve-me',
        'sclip.settings.maxItems': 100,
        'sclip.settings.themeMode': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = SettingsService(prefs);
      await s.resetAll();
      expect(prefs.getKeys(), isNot(contains('sclip.settings.maxItems')));
      expect(prefs.getKeys(), isNot(contains('sclip.settings.themeMode')));
      // Foreign key must survive a targeted reset — we only touch keys
      // under the sclip namespace, not anything else SharedPreferences
      // might be holding on behalf of other plugins.
      expect(prefs.getString('other_plugin.something'), 'preserve-me');
    });
  });

  group('regression: ClipboardEntry bytes never reach SharedPreferences', () {
    test('all persisted keys are sclip.settings.* scalars', () async {
      final s = await SettingsService.load();
      // Write every supported setting once to exercise the full surface.
      await s.setThemeMode(ThemeMode.dark);
      await s.setMaxItems(50);
      await s.setSensitiveFilterEnabled(false);
      await s.setAutoHideOnBlur(false);
      await s.setAlwaysOnTopDefault(true);
      await s.setPollingIntervalMs(250);
      await s.setClearOnStartup(true);
      await s.setToggleHotkey(
        HotKey(
          key: PhysicalKeyboardKey.keyV,
          modifiers: const [HotKeyModifier.meta, HotKeyModifier.shift],
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      // Every key we own must live under the sclip namespace. A regression
      // that persists a ClipboardEntry (even partially) would either show
      // up with a different prefix or with a base64/bytes-shaped value.
      for (final k in keys) {
        expect(
          k,
          startsWith(SettingsService.prefix),
          reason: 'Unexpected key outside sclip namespace: $k',
        );
      }
      // Sanity-check value shapes — no large blobs, no list-of-int, no
      // strings that look like base64 of raster bytes.
      for (final k in keys) {
        final value = prefs.get(k);
        expect(value, anyOf(isA<String>(), isA<int>(), isA<bool>()));
        if (value is String) {
          // An image byte payload base64-encoded is routinely >10KB even for
          // tiny PNGs. 4KB is a generous ceiling for a hotkey JSON blob
          // (our biggest scalar value) — anything larger is a red flag.
          expect(
            value.length,
            lessThan(4096),
            reason: 'Suspiciously large string in prefs for key $k',
          );
        }
      }
    });
  });
}
