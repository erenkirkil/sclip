import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/services/entry_filter.dart';

List<ClipboardEntry> _sample() => [
  ClipboardEntry.text('IŞIK hüzmesi'),
  ClipboardEntry.text('Gözlük siparişi'),
  ClipboardEntry.url(Uri.parse('https://ornek.com/rapor')),
  ClipboardEntry.pdf(Uint8List.fromList([0x25, 0x50])),
  ClipboardEntry.files([Uri.file('/tmp/sclip/notlar.txt')]),
];

void main() {
  group('filterEntries', () {
    test('blank query returns every entry in the original order', () {
      final entries = _sample();
      final result = filterEntries(entries, '');
      expect(result.map((e) => e.id), entries.map((e) => e.id));
      // A fresh list, so the caller can never write through to the history.
      expect(identical(result, entries), isFalse);
    });

    test('whitespace-only query is treated as no filter', () {
      final entries = _sample();
      expect(filterEntries(entries, '   \n\t').length, entries.length);
    });

    test('folds the query the same way as the index', () {
      final entries = _sample();
      expect(filterEntries(entries, 'isik').single.text, 'IŞIK hüzmesi');
      expect(filterEntries(entries, 'IŞIK').single.text, 'IŞIK hüzmesi');
      expect(filterEntries(entries, 'ışık').single.text, 'IŞIK hüzmesi');
      expect(filterEntries(entries, 'gozluk').single.text, 'Gözlük siparişi');
      expect(filterEntries(entries, 'GÖZLÜK').single.text, 'Gözlük siparişi');
    });

    test('matches the tag haystacks of binary types', () {
      final entries = _sample();
      expect(filterEntries(entries, 'pdf').single.type, ClipboardEntryType.pdf);
      expect(
        filterEntries(entries, 'notlar').single.type,
        ClipboardEntryType.files,
      );
      expect(
        filterEntries(entries, 'dosya').single.type,
        ClipboardEntryType.files,
      );
    });

    test('keeps the original order among the matches', () {
      final entries = _sample();
      final result = filterEntries(entries, 'i');
      final expected = entries
          .where((e) => e.searchIndex.contains('i'))
          .map((e) => e.id)
          .toList();
      expect(result.map((e) => e.id).toList(), expected);
      expect(result.length, greaterThan(1));
    });

    test('no match yields an empty list', () {
      expect(filterEntries(_sample(), 'zzzyx'), isEmpty);
    });

    test('never mutates the input list', () {
      final entries = _sample();
      final idsBefore = entries.map((e) => e.id).toList();
      filterEntries(entries, 'isik');
      filterEntries(entries, '');
      filterEntries(entries, 'zzzyx');
      expect(entries.map((e) => e.id).toList(), idsBefore);
    });

    test('result is fixed-length, so mutation fails loudly', () {
      final entries = _sample();
      expect(
        () => filterEntries(entries, 'isik').add(entries.first),
        throwsUnsupportedError,
      );
      expect(
        () => filterEntries(entries, '').removeAt(0),
        throwsUnsupportedError,
      );
    });
  });
}
