import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';

void main() {
  group('ClipboardEntry', () {
    test('text factory stores value and type', () {
      final e = ClipboardEntry.text('hello');
      expect(e.type, ClipboardEntryType.text);
      expect(e.text, 'hello');
      expect(e.preview, 'hello');
    });

    test('url factory stores uri', () {
      final e = ClipboardEntry.url(Uri.parse('https://example.com'));
      expect(e.type, ClipboardEntryType.url);
      expect(e.uris?.first.host, 'example.com');
    });

    test('image preview reports size', () {
      final bytes = Uint8List.fromList(List.filled(2048, 1));
      final e = ClipboardEntry.image(bytes);
      expect(e.type, ClipboardEntryType.image);
      expect(e.preview, contains('KB'));
    });

    test('text preview truncates', () {
      final long = 'x' * 200;
      final e = ClipboardEntry.text(long);
      expect(e.preview.length, lessThanOrEqualTo(121));
      expect(e.preview.endsWith('…'), isTrue);
    });

    test('looksLikeUrl detects http and rejects plain text', () {
      expect(ClipboardEntry.looksLikeUrl('https://x.com/a?b=1'), isTrue);
      expect(ClipboardEntry.looksLikeUrl('http://x'), isTrue);
      expect(ClipboardEntry.looksLikeUrl('mailto:a@b.c'), isTrue);
      expect(ClipboardEntry.looksLikeUrl('just some text'), isFalse);
      expect(ClipboardEntry.looksLikeUrl('line1\nhttps://x.com'), isFalse);
      expect(ClipboardEntry.looksLikeUrl(''), isFalse);
    });

    test('looksLikeColor detects hex and rgb, rejects plain text', () {
      expect(ClipboardEntry.looksLikeColor('#ff0000'), isTrue);
      expect(ClipboardEntry.looksLikeColor('ff0000'), isTrue);
      expect(ClipboardEntry.looksLikeColor('#f00'), isTrue);
      expect(ClipboardEntry.looksLikeColor('#ff0000aa'), isTrue);
      expect(ClipboardEntry.looksLikeColor('rgb(255, 0, 0)'), isTrue);
      expect(ClipboardEntry.looksLikeColor('rgba(255,0,0,0.5)'), isTrue);
      expect(ClipboardEntry.looksLikeColor('hello'), isFalse);
      expect(ClipboardEntry.looksLikeColor('ff00'), isFalse);
      expect(ClipboardEntry.looksLikeColor('#ggg'), isFalse);
    });

    test('color factory normalizes and parses to ARGB', () {
      final e1 = ClipboardEntry.color('ff0000');
      expect(e1.type, ClipboardEntryType.color);
      expect(e1.text, '#ff0000');
      expect(e1.toArgb32(), 0xFFFF0000);

      final e2 = ClipboardEntry.color('#f00');
      expect(e2.toArgb32(), 0xFFFF0000);

      final e3 = ClipboardEntry.color('#00ff0080');
      expect(e3.toArgb32(), 0x8000FF00);

      final e4 = ClipboardEntry.color('rgb(0, 0, 255)');
      expect(e4.toArgb32(), 0xFF0000FF);
    });

    test('ids are unique', () {
      final ids = List.generate(50, (_) => ClipboardEntry.text('a').id);
      expect(ids.toSet().length, ids.length);
    });

    test('contentHash is stable for identical content across instances', () {
      final a = ClipboardEntry.text('same content');
      final b = ClipboardEntry.text('same content');
      expect(a.contentHash, b.contentHash);
      expect(a.id, isNot(b.id));
    });

    test('contentHash differs across types with equal text', () {
      final txt = ClipboardEntry.text('example.com');
      final url = ClipboardEntry.url(Uri.parse('https://example.com'));
      final color = ClipboardEntry.color('#ff0000');
      final txtColor = ClipboardEntry.text('#ff0000');
      expect(txt.contentHash, isNot(url.contentHash));
      expect(color.contentHash, isNot(txtColor.contentHash));
    });

    test('image contentHash reflects byte content', () {
      final a = ClipboardEntry.image(Uint8List.fromList([1, 2, 3, 4]));
      final b = ClipboardEntry.image(Uint8List.fromList([1, 2, 3, 4]));
      final c = ClipboardEntry.image(Uint8List.fromList([1, 2, 3, 5]));
      expect(a.contentHash, b.contentHash);
      expect(a.contentHash, isNot(c.contentHash));
    });

    test('touched keeps identity and hash, refreshes createdAt', () async {
      final a = ClipboardEntry.text('payload');
      await Future.delayed(const Duration(milliseconds: 5));
      final t = a.touched();
      expect(t.id, a.id);
      expect(t.contentHash, a.contentHash);
      expect(t.text, a.text);
      expect(t.createdAt.isAfter(a.createdAt), isTrue);
    });

    test('image factory tracks format tag', () {
      final jpeg = ClipboardEntry.image(
        Uint8List.fromList([0xff, 0xd8, 0xff]),
        format: ClipboardImageFormat.jpeg,
      );
      expect(jpeg.imageFormat, ClipboardImageFormat.jpeg);
      expect(jpeg.preview, startsWith('JPEG'));
    });

    test('imageSet stores bytes and per-image formats', () {
      final a = Uint8List.fromList(List.filled(1024, 1));
      final b = Uint8List.fromList(List.filled(2048, 2));
      final e = ClipboardEntry.imageSet(
        [a, b],
        formats: const [ClipboardImageFormat.jpeg, ClipboardImageFormat.png],
      );
      expect(e.type, ClipboardEntryType.imageSet);
      expect(e.imagesBytes?.length, 2);
      expect(e.imagesFormats, [
        ClipboardImageFormat.jpeg,
        ClipboardImageFormat.png,
      ]);
    });

    test('imageSet preview counts images and sums size', () {
      final e = ClipboardEntry.imageSet([
        Uint8List.fromList(List.filled(1024, 1)),
        Uint8List.fromList(List.filled(2048, 2)),
        Uint8List.fromList(List.filled(1024, 3)),
      ]);
      expect(e.preview, '3 resim · 4KB');
    });

    test('imageSet contentHash is stable for same contents in same order', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([5, 6, 7, 8]);
      final s1 = ClipboardEntry.imageSet([a, b]);
      final s2 = ClipboardEntry.imageSet([
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List.fromList([5, 6, 7, 8]),
      ]);
      expect(s1.contentHash, s2.contentHash);
      expect(s1.id, isNot(s2.id));
    });

    test('imageSet contentHash is order-sensitive', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([5, 6, 7, 8]);
      final s1 = ClipboardEntry.imageSet([a, b]);
      final s2 = ClipboardEntry.imageSet([b, a]);
      expect(s1.contentHash, isNot(s2.contentHash));
    });

    test('imageSet contentHash is distinct from single image', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final single = ClipboardEntry.image(bytes);
      final set = ClipboardEntry.imageSet([bytes, bytes]);
      expect(single.contentHash, isNot(set.contentHash));
    });

    test('imageSet touched preserves bytes, formats, hash, and id', () async {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([4, 5, 6]);
      final e = ClipboardEntry.imageSet([a, b]);
      await Future.delayed(const Duration(milliseconds: 5));
      final t = e.touched();
      expect(t.id, e.id);
      expect(t.contentHash, e.contentHash);
      expect(t.imagesBytes, e.imagesBytes);
      expect(t.imagesFormats, e.imagesFormats);
      expect(t.createdAt.isAfter(e.createdAt), isTrue);
    });

    test('pdf factory stores bytes and renders size preview', () {
      final bytes = Uint8List.fromList(List.filled(2048, 0xAB));
      final e = ClipboardEntry.pdf(bytes);
      expect(e.type, ClipboardEntryType.pdf);
      expect(e.pdfBytes, bytes);
      expect(e.preview, startsWith('PDF · '));
      expect(e.preview, contains('KB'));
    });

    test('pdf contentHash reflects byte content', () {
      final a = ClipboardEntry.pdf(Uint8List.fromList([1, 2, 3, 4]));
      final b = ClipboardEntry.pdf(Uint8List.fromList([1, 2, 3, 4]));
      final c = ClipboardEntry.pdf(Uint8List.fromList([1, 2, 3, 5]));
      expect(a.contentHash, b.contentHash);
      expect(a.contentHash, isNot(c.contentHash));
    });

    test('pdf touched preserves bytes, hash, and id', () async {
      final bytes = Uint8List.fromList([9, 8, 7]);
      final e = ClipboardEntry.pdf(bytes);
      await Future.delayed(const Duration(milliseconds: 5));
      final t = e.touched();
      expect(t.id, e.id);
      expect(t.contentHash, e.contentHash);
      expect(t.pdfBytes, e.pdfBytes);
      expect(t.createdAt.isAfter(e.createdAt), isTrue);
    });

    test('richText factory stores plain and html side-by-side', () {
      final e = ClipboardEntry.richText(
        plainText: 'hello world',
        html: '<p><b>hello</b> world</p>',
      );
      expect(e.type, ClipboardEntryType.richText);
      expect(e.text, 'hello world');
      expect(e.richTextHtml, '<p><b>hello</b> world</p>');
      expect(e.preview, 'hello world');
    });

    test('richText contentHash differs from plain text with same body', () {
      final plain = ClipboardEntry.text('hello world');
      final rich = ClipboardEntry.richText(
        plainText: 'hello world',
        html: '<p>hello world</p>',
      );
      // Different types must yield different hashes so dedup doesn't
      // silently swallow a richer copy when a bare-text entry is at the head.
      expect(rich.contentHash, isNot(plain.contentHash));
    });

    test('richText contentHash captures html differences', () {
      final a = ClipboardEntry.richText(plainText: 'same', html: '<p>a</p>');
      final b = ClipboardEntry.richText(plainText: 'same', html: '<p>b</p>');
      expect(a.contentHash, isNot(b.contentHash));
    });

    test('richText touched preserves html and identity', () async {
      final e = ClipboardEntry.richText(
        plainText: 'snippet',
        html: '<i>snippet</i>',
      );
      await Future.delayed(const Duration(milliseconds: 5));
      final t = e.touched();
      expect(t.id, e.id);
      expect(t.contentHash, e.contentHash);
      expect(t.richTextHtml, e.richTextHtml);
      expect(t.text, e.text);
      expect(t.createdAt.isAfter(e.createdAt), isTrue);
    });

    test('files preview shows basename only for single file', () {
      final e = ClipboardEntry.files([Uri.file('/tmp/sclip/a.png')]);
      expect(e.preview, 'a.png');
    });

    test('files preview lists basenames up to three entries', () {
      final e = ClipboardEntry.files([
        Uri.file('/tmp/sclip/a.png'),
        Uri.file('/tmp/sclip/b.pdf'),
        Uri.file('/tmp/sclip/c.txt'),
      ]);
      expect(e.preview, '3 dosya: a.png, b.pdf, c.txt');
    });

    test('files preview collapses overflow into "+ N daha"', () {
      final e = ClipboardEntry.files([
        Uri.file('/tmp/sclip/a.png'),
        Uri.file('/tmp/sclip/b.pdf'),
        Uri.file('/tmp/sclip/c.txt'),
        Uri.file('/tmp/sclip/d.docx'),
        Uri.file('/tmp/sclip/e.zip'),
      ]);
      expect(e.preview, '5 dosya: a.png, b.pdf, c.txt + 2 daha');
    });
  });
}
