import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';
import 'package:sclip/ui/search_bar.dart';

import 'search_harness.dart';

void main() {
  testWidgets('boş durum: sıfır sonuçta sorgulu metin çıkar', (tester) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();
    expect(find.textContaining('Henüz içerik yok'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();

    expect(find.text("'zzzz' için sonuç yok"), findsOneWidget);
    expect(
      find.textContaining('Henüz içerik yok'),
      findsNothing,
      reason: 'geçmiş dolu, yanıltıcı metin gösterilmemeli',
    );
  });

  testWidgets('boş durum: geçmiş boşken eski metin korunur', (tester) async {
    final provider = HistoryProvider(maxItems: 10);
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();

    expect(find.text('Henüz içerik yok — bir şey kopyala'), findsOneWidget);
  });

  testWidgets('boş durum: sıfır sonuçta klavye ölmüyor', (tester) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text("'zzzz' için sonuç yok"), findsOneWidget);

    // ArrowDown has nowhere to go; it must be a no-op, not a crash, and
    // must not move focus out of the field.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'harness-search');

    // Editing still works from the same focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(find.text("'zzz' için sonuç yok"), findsOneWidget);
    expect(provider.length, 2);

    // Esc still closes and restores the unfiltered list.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(HistorySearchBar), findsNothing);
    expect(find.text('mavi defter'), findsOneWidget);
    expect(find.text('yesil silgi'), findsOneWidget);
  });
}
