import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/services/entry_filter.dart';

/// ~8 KB of Turkish filler — the size a long copy actually indexes at —
/// with the only 'z' of the whole corpus parked at the very end. Every
/// query below therefore scans the full haystack instead of matching on
/// the first few characters, which is the worst case a keystroke can hit.
String _filler() {
  final b = StringBuffer();
  while (b.length < 8100) {
    b.write('Lorem İpsum dolor sit amet ŞUBAT raporu ÇAĞRI listesi ');
  }
  return '$b ZÜMRÜT';
}

/// [count] entries covering all nine types, in the round-robin a busy
/// history actually looks like.
List<ClipboardEntry> _mixedHistory(int count) {
  final filler = _filler();
  final bytes = Uint8List.fromList(List.filled(64, 7));
  final entries = <ClipboardEntry>[];
  for (var i = 0; i < count; i++) {
    switch (i % 9) {
      case 0:
        entries.add(ClipboardEntry.text('$filler $i'));
      case 1:
        entries.add(
          ClipboardEntry.richText(
            plainText: '$filler $i',
            html: '<p>$filler $i</p>',
          ),
        );
      case 2:
        entries.add(ClipboardEntry.url(Uri.parse('https://ornek.com/x$i')));
      case 3:
        entries.add(ClipboardEntry.color('#ff00$i$i'));
      case 4:
        entries.add(
          ClipboardEntry.files([
            Uri.file('/tmp/sclip/rapor-$i.pdf'),
            Uri.file('/tmp/sclip/notlar-$i.txt'),
          ]),
        );
      case 5:
        entries.add(ClipboardEntry.image(bytes));
      case 6:
        entries.add(
          ClipboardEntry.imageSet([
            bytes,
            Uint8List.fromList([8, 9]),
          ]),
        );
      case 7:
        entries.add(ClipboardEntry.pdf(bytes));
      case 8:
        entries.add(ClipboardEntry.svg('<svg><path fill="#f00"/></svg>'));
    }
  }
  return entries;
}

void main() {
  group('search index budget', () {
    test('a 2 MB text entry is clipped to the 8192-char cap', () {
      final huge = 'a' * (2 * 1024 * 1024);
      final e = ClipboardEntry.text(huge);
      expect(e.text?.length, 2 * 1024 * 1024);
      expect(e.searchIndex.length, 8192);
      expect(e.searchIndex, 'a' * 8192);
    });

    test('clipping happens before normalization, not after', () {
      final huge = 'IŞIK ' * (400 * 1024);
      final e = ClipboardEntry.text(huge);
      final sw = Stopwatch()..start();
      final index = e.searchIndex;
      sw.stop();
      expect(index.length, lessThanOrEqualTo(8192));
      // Measured: ~2ms cutting first, ~110ms normalizing the full 2 MB and
      // cutting afterwards.
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: 'index build took ${sw.elapsedMilliseconds}ms',
      );
    });
  });

  group('filterEntries cost per keystroke', () {
    test('100 keystrokes over a 100-entry mixed history stay cheap', () {
      const passes = 100;
      final entries = _mixedHistory(100);
      expect(entries.length, 100);

      // Warm-up: the first pass materializes all 100 late-final indexes,
      // which is ingest cost, not typing cost.
      expect(filterEntries(entries, 'zumrut'), isNotEmpty);

      const queries = ['z', 'zu', 'zum', 'zumr'];
      var matches = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < passes; i++) {
        matches += filterEntries(entries, queries[i % queries.length]).length;
      }
      sw.stop();

      expect(matches, greaterThan(0));
      // Measured on the dev machine (3.44.8, JIT): ~37ms with searchIndex
      // cached on the entry, ~754ms when it is recomputed per keystroke.
      expect(
        sw.elapsedMilliseconds,
        lessThan(250),
        reason: '$passes keystrokes took ${sw.elapsedMilliseconds}ms',
      );
    });
  });
}
