import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sclip/main.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';
import 'package:sclip/ui/history_list.dart';
import 'package:sclip/ui/search_bar.dart';

import 'search_harness.dart';

void main() {
  testWidgets('arama kutusunda Backspace geçmişten silmez', (tester) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();
    expect(provider.length, 2);

    // enterText focuses the field first, so every key below lands on the
    // query — the exact situation HistoryList's per-tile Backspace →
    // removeById binding would turn into silent data loss.
    await tester.enterText(find.byType(TextField), 'def');
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
    }

    expect(
      provider.length,
      2,
      reason: 'Backspace yalnızca sorguyu düzenler, entry silmez',
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(find.text('mavi defter'), findsOneWidget);
    expect(find.text('yesil silgi'), findsOneWidget);
  });

  testWidgets('arama alanı HistoryList alt ağacının dışında', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.load();
    final settings = SettingsProvider(service);

    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    await tester.tap(find.byTooltip('Ara'));
    await tester.pump();

    expect(find.byType(HistorySearchBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(HistoryList),
        matching: find.byType(HistorySearchBar),
      ),
      findsNothing,
      reason: 'K-03: yerleşim koşullu kontrol değil, yapısal garanti',
    );
  });
}
