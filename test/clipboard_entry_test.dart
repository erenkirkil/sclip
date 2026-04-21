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
  });
}
