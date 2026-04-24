import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';

void main() {
  group('HistoryProvider', () {
    test('add inserts at head and notifies listeners', () {
      final p = HistoryProvider();
      var notified = 0;
      p.addListener(() => notified++);

      p.add(ClipboardEntry.text('a'));
      p.add(ClipboardEntry.text('b'));

      expect(p.entries.map((e) => e.text).toList(), ['b', 'a']);
      expect(notified, 2);
    });

    test('suppresses duplicate at head', () {
      final p = HistoryProvider();
      p.add(ClipboardEntry.text('same'));
      var notified = 0;
      p.addListener(() => notified++);

      p.add(ClipboardEntry.text('same'));
      expect(p.length, 1);
      expect(notified, 0);
    });

    test('moves duplicate to head when re-copied', () {
      final p = HistoryProvider();
      p.add(ClipboardEntry.text('a'));
      p.add(ClipboardEntry.text('b'));
      p.add(ClipboardEntry.text('c'));
      expect(p.entries.map((e) => e.text).toList(), ['c', 'b', 'a']);

      p.add(ClipboardEntry.text('a'));
      expect(p.entries.map((e) => e.text).toList(), ['a', 'c', 'b']);
      expect(p.length, 3);
    });

    test('enforces FIFO cap', () {
      final p = HistoryProvider(maxItems: 3);
      for (var i = 0; i < 5; i++) {
        p.add(ClipboardEntry.text('v$i'));
      }
      expect(p.length, 3);
      expect(p.entries.map((e) => e.text).toList(), ['v4', 'v3', 'v2']);
    });

    test('removeAt and removeById', () {
      final p = HistoryProvider();
      final a = ClipboardEntry.text('a');
      final b = ClipboardEntry.text('b');
      final c = ClipboardEntry.text('c');
      p.add(a);
      p.add(b);
      p.add(c);

      p.removeAt(1);
      expect(p.entries.map((e) => e.text).toList(), ['c', 'a']);

      p.removeById(a.id);
      expect(p.entries.map((e) => e.text).toList(), ['c']);

      p.removeAt(99);
      expect(p.length, 1);
    });

    test('clear empties the list and notifies only when non-empty', () {
      final p = HistoryProvider();
      var notified = 0;
      p.addListener(() => notified++);

      p.clear();
      expect(notified, 0);

      p.add(ClipboardEntry.text('x'));
      p.clear();
      expect(p.isEmpty, isTrue);
      expect(notified, 2);
    });

    test('touch refreshes createdAt and moves entry to head', () async {
      final p = HistoryProvider();
      final a = ClipboardEntry.text('a');
      p.add(a);
      p.add(ClipboardEntry.text('b'));
      p.add(ClipboardEntry.text('c'));

      // Ensure some wall-clock delta is measurable.
      await Future.delayed(const Duration(milliseconds: 5));

      p.touch(a.id);

      expect(p.entries.first.id, a.id);
      expect(p.entries.first.text, 'a');
      expect(
        p.entries.first.createdAt.isAfter(a.createdAt),
        isTrue,
        reason: 'touched entry should have a fresh timestamp',
      );
    });

    test('touch is a no-op for unknown ids', () {
      final p = HistoryProvider();
      p.add(ClipboardEntry.text('a'));
      var notified = 0;
      p.addListener(() => notified++);

      p.touch('does-not-exist');
      expect(notified, 0);
    });

    test('drops image entries larger than maxImageBytes', () {
      final p = HistoryProvider(maxImageBytes: 100);
      final small = ClipboardEntry.image(
        Uint8List.fromList(List.filled(50, 1)),
      );
      final big = ClipboardEntry.image(
        Uint8List.fromList(List.filled(200, 1)),
      );

      p.add(small);
      p.add(big);

      expect(p.length, 1);
      expect(p.entries.first.id, small.id);
    });

    test('drops imageSet entries whose total bytes exceed maxImageBytes', () {
      final p = HistoryProvider(maxImageBytes: 100);
      final fits = ClipboardEntry.imageSet([
        Uint8List.fromList(List.filled(30, 1)),
        Uint8List.fromList(List.filled(40, 2)),
      ]);
      final overflows = ClipboardEntry.imageSet([
        Uint8List.fromList(List.filled(60, 1)),
        Uint8List.fromList(List.filled(60, 2)),
      ]);

      p.add(fits);
      p.add(overflows);

      expect(p.length, 1);
      expect(p.entries.first.id, fits.id);
    });

    test('imageSet dedup moves same set to head', () {
      final p = HistoryProvider();
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([4, 5, 6]);

      p.add(ClipboardEntry.imageSet([a, b]));
      p.add(ClipboardEntry.text('other'));
      // Re-ingesting same set with identical bytes — should dedupe, not
      // accumulate, mirroring the single-image behavior.
      p.add(ClipboardEntry.imageSet([
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ]));

      expect(p.length, 2);
      expect(p.entries.first.type, ClipboardEntryType.imageSet);
    });

    test('hash-based dedup treats rebuilt entries with same content as one', () {
      final p = HistoryProvider();

      // Simulates: user copies same text again from outside — clipboard
      // service produces a fresh entry (new id, new createdAt) but same
      // contentHash. Should dedupe rather than accumulate.
      p.add(ClipboardEntry.text('shared'));
      p.add(ClipboardEntry.text('other'));
      p.add(ClipboardEntry.text('shared'));

      expect(p.length, 2);
      expect(p.entries.first.text, 'shared');
    });
  });
}
