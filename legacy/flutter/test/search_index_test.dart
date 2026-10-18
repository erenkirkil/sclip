import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';

void main() {
  group('ClipboardEntry.searchIndex', () {
    test('is normalized like a query is', () {
      final e = ClipboardEntry.text('IŞIK ve Gözlük');
      expect(e.searchIndex, 'isik ve gozluk');
    });

    test('text indexes the whole body, not the 120-char preview', () {
      final body = '${'a' * 500} çilingir';
      final e = ClipboardEntry.text(body);
      expect(e.preview, isNot(contains('çilingir')));
      expect(e.searchIndex, contains('cilingir'));
    });

    test('url indexes both the display text and the URI', () {
      final e = ClipboardEntry.url(
        Uri.parse('mailto:ayse@ornek.com'),
        displayText: 'ayse@ornek.com',
      );
      expect(e.searchIndex, contains('ayse@ornek.com'));
      expect(e.searchIndex, contains('mailto:'));

      final plain = ClipboardEntry.url(Uri.parse('https://ornek.com/Ürün'));
      expect(plain.searchIndex, contains('ornek.com'));
    });

    test('color indexes the normalized hex', () {
      final e = ClipboardEntry.color('FF0000');
      expect(e.searchIndex, '#ff0000');
    });

    test('richText indexes plain text only, never the markup', () {
      final e = ClipboardEntry.richText(
        plainText: 'Şubat raporu',
        html: '<p><strong>Şubat</strong> raporu</p>',
      );
      expect(e.searchIndex, 'subat raporu');
      expect(e.searchIndex, isNot(contains('strong')));
    });

    test('files index basenames plus a dosya tag, never full paths', () {
      final e = ClipboardEntry.files([
        Uri.file('/tmp/sclip/Şubat Raporu.pdf'),
        Uri.file('/tmp/sclip/notlar.txt'),
      ]);
      expect(e.searchIndex, contains('dosya'));
      expect(e.searchIndex, contains('subat raporu.pdf'));
      expect(e.searchIndex, contains('notlar.txt'));
      expect(e.searchIndex, isNot(contains('tmp')));
    });

    test('files index every name, unlike the "+ N daha" preview', () {
      final e = ClipboardEntry.files([
        Uri.file('/tmp/sclip/a.png'),
        Uri.file('/tmp/sclip/b.pdf'),
        Uri.file('/tmp/sclip/c.txt'),
        Uri.file('/tmp/sclip/d.docx'),
        Uri.file('/tmp/sclip/gizli.zip'),
      ]);
      expect(e.preview, isNot(contains('gizli.zip')));
      expect(e.searchIndex, contains('gizli.zip'));
    });

    test('image indexes type tags', () {
      final png = ClipboardEntry.image(Uint8List.fromList([1, 2, 3]));
      expect(png.searchIndex, 'resim png');

      final jpeg = ClipboardEntry.image(
        Uint8List.fromList([1, 2, 3]),
        format: ClipboardImageFormat.jpeg,
      );
      expect(jpeg.searchIndex, 'resim jpeg');
    });

    test('imageSet indexes distinct format tags once', () {
      final e = ClipboardEntry.imageSet(
        [
          Uint8List.fromList([1]),
          Uint8List.fromList([2]),
          Uint8List.fromList([3]),
        ],
        formats: const [
          ClipboardImageFormat.png,
          ClipboardImageFormat.jpeg,
          ClipboardImageFormat.png,
        ],
      );
      expect(e.searchIndex, 'resim png jpeg');
    });

    test('pdf indexes the pdf tag', () {
      final e = ClipboardEntry.pdf(Uint8List.fromList([0x25, 0x50]));
      expect(e.searchIndex, 'pdf');
    });

    test('svg indexes the tag only, never the raw XML', () {
      final e = ClipboardEntry.svg(
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<path fill="#ff0000" d="M0 0h10v10H0z"/></svg>',
      );
      expect(e.searchIndex, 'svg');
      expect(e.searchIndex, isNot(contains('path')));
      expect(e.searchIndex, isNot(contains('fill')));
    });

    test('touched() keeps the entry searchable', () {
      final e = ClipboardEntry.text('ÇAĞRI listesi');
      expect(e.touched().searchIndex, e.searchIndex);
    });
  });
}
