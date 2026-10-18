import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sclip/main.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';
import 'package:sclip/ui/home_page.dart';
import 'package:sclip/ui/search_bar.dart';
import 'package:sclip/ui/settings_page.dart';

void main() {
  const windowChannel = MethodChannel('sclip/window');
  const windowManagerChannel = MethodChannel('window_manager');

  testWidgets('Esc hides window when no dialog or search bar is open', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.load();
    final settings = SettingsProvider(service);

    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();
    calls.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, contains('hideAndDeactivate'));
  });

  testWidgets('Esc closes search bar first, then second Esc hides window', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.load();
    final settings = SettingsProvider(service);

    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    await tester.tap(find.byTooltip('Ara'));
    await tester.pump();
    expect(find.byType(HistorySearchBar), findsOneWidget);
    calls.clear();

    // First Esc closes the search bar without hiding the window.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HistorySearchBar), findsNothing);
    expect(calls, isNot(contains('hideAndDeactivate')));

    // Second Esc hides the window.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, contains('hideAndDeactivate'));
  });

  testWidgets(
    'Esc closes Settings dialog first, then second Esc hides window',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, (call) async {
            calls.add(call.method);
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async => true);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowManagerChannel, null);
      });

      SharedPreferences.setMockInitialValues({});
      final service = await SettingsService.load();
      final settings = SettingsProvider(service);

      await tester.pumpWidget(SclipApp(settings: settings));
      await tester.pump();

      await tester.tap(find.byTooltip('Ayarlar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SettingsPage), findsOneWidget);
      calls.clear();

      // First Esc closes the settings dialog without hiding the window.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SettingsPage), findsNothing);
      expect(calls, isNot(contains('hideAndDeactivate')));

      // Second Esc hides the window.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, contains('hideAndDeactivate'));
    },
  );

  testWidgets(
    'when autoHideOnBlur is false and window loses focus, toggle shows/activates instead of hiding',
    (tester) async {
      final windowCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, (call) async {
            windowCalls.add(call.method);
            if (call.method == 'screenLayout') {
              return <String, dynamic>{
                'cursor': <String, dynamic>{'dx': 0, 'dy': 0},
                'displays': <Map<String, dynamic>>[],
              };
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async {
            if (call.method == 'isVisible') return true;
            if (call.method == 'isFocused') return false;
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowManagerChannel, null);
      });

      SharedPreferences.setMockInitialValues({
        'sclip.settings.autoHideOnBlur': false,
      });
      final service = await SettingsService.load();
      final settings = SettingsProvider(service);

      await tester.pumpWidget(SclipApp(settings: settings));
      await tester.pump();

      final homeState = tester.state<HomePageState>(find.byType(HomePage));
      // Simulate clicking outside the window while autoHideOnBlur is false:
      // window stays visible, but loses focus.
      homeState.onWindowBlur();
      windowCalls.clear();

      // Clicking "Göster / Gizle" in the tray menu must bring the window to
      // the front (showAndActivate), NOT hide it (hideAndDeactivate).
      unawaited(homeState.debugToggleWindow());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(windowCalls, contains('showAndActivate'));
      expect(windowCalls, isNot(contains('hideAndDeactivate')));
    },
  );
}
