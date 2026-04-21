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
  });
}
