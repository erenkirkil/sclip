import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';
import 'package:sclip/ui/entry_tiles/image_set_tile.dart';

import 'search_harness.dart';

/// 1×1 transparent PNG. Real bytes so Image.memory doesn't take the
/// errorBuilder path; nothing here depends on the decode completing.
final Uint8List _pngPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

FocusNode _thumbNodeByLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<FocusableActionDetector>(find.byType(FocusableActionDetector))
      .map((w) => w.focusNode)
      .firstWhere((n) => n?.debugLabel == label)!;
}

void main() {
  testWidgets('filtre: imageSet ızgara konumu korunuyor', (tester) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(
      ClipboardEntry.imageSet(<Uint8List>[
        _pngPixel,
        _pngPixel,
        _pngPixel,
        _pngPixel,
      ]),
    );
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();
    expect(find.byType(ImageSetTile), findsOneWidget);

    // Focus the third thumbnail directly: driving there with arrow keys
    // would depend on the Wrap's pixel geometry, which is not what this
    // test is about.
    final thumb2 = _thumbNodeByLabel(tester, 'entry-thumb-2');
    thumb2.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'entry-thumb-2');

    // 'resim' matches the imageSet's type label only, so the set moves
    // from index 1 to index 0 while the two text entries drop out.
    final state = tester.state<SearchHarnessState>(find.byType(SearchHarness));
    state.setQuery('resim');
    await tester.pump();
    await tester.pump();

    expect(find.byType(ImageSetTile), findsOneWidget);
    expect(find.text('yesil silgi'), findsNothing);
    expect(
      identical(FocusManager.instance.primaryFocus, thumb2),
      isTrue,
      reason: 'element yeniden kullanılmalı, state sıfırlanmamalı',
    );
  });

  testWidgets('filtre: ilk sıraya çıkan tile odaklı düğümü öldürmüyor', (
    tester,
  ) async {
    final provider = HistoryProvider(maxItems: 10);
    provider.add(ClipboardEntry.text('kirmizi kalem'));
    provider.add(ClipboardEntry.text('mavi defter'));
    provider.add(ClipboardEntry.text('yesil silgi'));
    addTearDown(provider.dispose);

    await tester.pumpWidget(SearchHarness(provider: provider));
    await tester.pump();

    // Index 0 autofocuses; step down onto index 1, whose tile owns its
    // own FocusNode ('entry-tile').
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'entry-tile');

    // 'defter' promotes that same tile to index 0, which flips its
    // focusNode prop from null to the external first-item node.
    final state = tester.state<SearchHarnessState>(find.byType(SearchHarness));
    state.setQuery('defter');
    await tester.pump();
    await tester.pump();

    expect(find.text('mavi defter'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'harness-first-item',
      reason: 'odak devredilmeli, düşmemeli',
    );
  });
}
