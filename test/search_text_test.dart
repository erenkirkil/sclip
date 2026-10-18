import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/services/search_text.dart';

void main() {
  group('normalizeForSearch', () {
    test('folds every Turkish I to ASCII i', () {
      // Dart lowercases 'IŞIK' to 'işik' and 'İ' to 'i', but leaves 'ı'
      // alone — all four must land on the same letter.
      expect(normalizeForSearch('IŞIK'), 'isik');
      expect(normalizeForSearch('ışık'), 'isik');
      expect(normalizeForSearch('Işık'), 'isik');
      expect(normalizeForSearch('İSTANBUL'), 'istanbul');
      expect(normalizeForSearch('ISTANBUL'), 'istanbul');
      expect(normalizeForSearch('istanbul'), 'istanbul');
    });

    test('strips Turkish diacritics', () {
      expect(normalizeForSearch('Gözlük'), 'gozluk');
      expect(normalizeForSearch('GÖZLÜK'), 'gozluk');
      expect(normalizeForSearch('ÇAĞRI'), 'cagri');
      expect(normalizeForSearch('çağrı'), 'cagri');
      expect(normalizeForSearch('ŞEHİR'), 'sehir');
      expect(normalizeForSearch('KÂĞIT'), 'kagit');
    });

    test('collapses whitespace runs and trims the ends', () {
      expect(
        normalizeForSearch('  çok   satırlı\nmetin\t'),
        'cok satirli metin',
      );
      expect(normalizeForSearch('a b'), 'a b');
    });

    test('blank and whitespace-only input normalize to empty', () {
      expect(normalizeForSearch(''), '');
      expect(normalizeForSearch('   '), '');
      expect(normalizeForSearch('\n\t '), '');
    });

    test('query and content land on the same form', () {
      expect(normalizeForSearch('isik'), normalizeForSearch('IŞIK'));
      expect(normalizeForSearch('gozluk'), normalizeForSearch('Gözlük'));
      expect(normalizeForSearch('sehir'), normalizeForSearch('şehir'));
    });

    test('leaves ASCII and non-BMP content intact', () {
      expect(normalizeForSearch('Hello World'), 'hello world');
      expect(normalizeForSearch('🎉 Şenlik'), '🎉 senlik');
    });

    test('is idempotent', () {
      const raw = '  İki   KELİME\tÖĞÜŞÇ  ';
      final once = normalizeForSearch(raw);
      expect(normalizeForSearch(once), once);
    });
  });
}
