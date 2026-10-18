import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sclip/main.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';
import 'package:sclip/providers/settings_provider.dart';
import 'package:sclip/services/settings_service.dart';
import 'package:sclip/ui/search_bar.dart';

import 'search_harness.dart';

void main() {
  testWidgets('odak: Esc çubuğu kapatır ve sorguyu temizler', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.load();
    final settings = SettingsProvider(service);

    await tester.pumpWidget(SclipApp(settings: settings));
    await tester.pump();

    await tester.tap(find.byTooltip('Ara'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'defter');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'defter',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(HistorySearchBar), findsNothing);

    // Reopening proves the query was dropped, not just hidden.
    await tester.tap(find.byTooltip('Ara'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('odak: aşağı ok listeye iner, ilk öğede yukarı ok kutuya döner', (
    tester,
  ) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();

    final state = tester.state<SearchHarnessState>(find.byType(SearchHarness));
    state.searchFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'harness-search');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'harness-first-item',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'harness-search');
  });

  testWidgets('odak: kutuda Enter ilk sonucu yapıştırır', (tester) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    final pasted = <String>[];
    await tester.pumpWidget(
      SearchHarness(
        provider: provider,
        onEntryTap: (entry) => pasted.add(entry.text ?? ''),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'defter');
    await tester.pump();
    // A physical Enter never reaches onSubmitted in a widget test — the
    // action arrives over the platform text-input channel.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(pasted, <String>['mavi defter']);
  });
}
