import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sclip/main.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';
import 'package:sclip/ui/entry_tiles/standard_tile.dart';
import 'package:sclip/ui/entry_tiles/tile_shared.dart';
import 'package:sclip/ui/hotkey_recorder_dialog.dart';
import 'package:sclip/ui/settings_page.dart';

// 1x1 transparent PNG for thumbnail layout tests.
final Uint8List _onePixelPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('app boots with empty state message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.load();
    final settings = SettingsProvider(service);
    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    expect(find.bySemanticsLabel('sclip'), findsOneWidget);
    expect(find.textContaining('Henüz içerik yok'), findsOneWidget);
  });

  for (final viewport in const [
    Size(220, 260),
    Size(260, 340),
    Size(320, 420),
    Size(380, 520),
  ]) {
    testWidgets('SettingsPage and HotkeyRecorderDialog fit without overflow at '
        '${viewport.width.toInt()}x${viewport.height.toInt()}', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});
      final service = await SettingsService.load();
      final settings = SettingsProvider(service);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsPage.show(
                    context,
                    settings: settings,
                    onHotkeyChange: (_) async => true,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Değiştir'));
      await tester.pumpAndSettle();
      expect(find.byType(HotkeyRecorderDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'StandardEntryTile renders 40x40 image leading unclipped and 28x28 trailing buttons',
    (tester) async {
      final entry = ClipboardEntry.image(_onePixelPng);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardEntryTile(
              entry: entry,
              onTap: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      final imageBox = tester.getSize(find.byType(Image));
      expect(imageBox, const Size(thumbExtent, thumbExtent));

      final deleteBox = tester.getSize(find.byType(IconButton));
      expect(deleteBox, const Size(trailingButtonExtent, trailingButtonExtent));
    },
  );
}
