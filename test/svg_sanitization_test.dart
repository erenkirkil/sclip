import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/services/clipboard_service.dart';

Uint8List _load(String name) {
  final f = File('test/fixtures/malicious_svg/$name');
  return f.readAsBytesSync();
}

void main() {
  group('isSafeSvgPayload — malicious fixtures rejected', () {
    test('billion laughs (recursive ENTITY expansion)', () {
      expect(ClipboardService.isSafeSvgPayload(_load('billion_laughs.svg')),
          isFalse);
    });

    test('external entity (SYSTEM file reference)', () {
      expect(ClipboardService.isSafeSvgPayload(_load('external_entity.svg')),
          isFalse);
    });

    test('XInclude injection', () {
      expect(
          ClipboardService.isSafeSvgPayload(_load('xinclude.svg')), isFalse);
    });

    test('payload above 20 MB hard cap', () {
      // Build 21 MB of benign SVG-ish bytes — content is irrelevant because
      // the size check short-circuits before inspection.
      final big = Uint8List(21 * 1024 * 1024);
      expect(ClipboardService.isSafeSvgPayload(big), isFalse);
    });

    test('ATTLIST declaration', () {
      final bytes = Uint8List.fromList(
        '<?xml version="1.0"?>\n<!ATTLIST foo bar CDATA #IMPLIED>\n<svg/>'
            .codeUnits,
      );
      expect(ClipboardService.isSafeSvgPayload(bytes), isFalse);
    });
  });

  group('isSafeSvgPayload — legitimate fixtures accepted', () {
    test('simple icon', () {
      expect(ClipboardService.isSafeSvgPayload(_load('simple_icon.svg')),
          isTrue);
    });

    test('figma-style export with gradient + defs', () {
      expect(
          ClipboardService.isSafeSvgPayload(_load('figma_like.svg')), isTrue);
    });

    test('multi-MB payload of legitimate SVG path data', () {
      // Real Figma/Illustrator exports frequently exceed 1 MB; verify that
      // the 20 MB cap doesn't bite benign assets.
      final header = '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg">';
      final footer = '</svg>';
      final filler = '<path d="${'M0,0 ' * 1500000}"/>';
      final doc = '$header$filler$footer';
      final bytes = Uint8List.fromList(doc.codeUnits);
      expect(bytes.length, greaterThan(1024 * 1024));
      expect(bytes.length, lessThan(20 * 1024 * 1024));
      expect(ClipboardService.isSafeSvgPayload(bytes), isTrue);
    });
  });

  group('isSafeSvgPayload — edge cases', () {
    test('empty payload is technically safe (ingestion discards separately)',
        () {
      expect(ClipboardService.isSafeSvgPayload(Uint8List(0)), isTrue);
    });

    test('non-UTF-8 bytes do not throw, treated as safe unless flagged', () {
      // allowMalformed decoding should keep the scan from crashing on
      // garbage bytes; the resulting text just won't contain our markers.
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x00, 0x00, 0x80, 0x81]);
      expect(() => ClipboardService.isSafeSvgPayload(bytes), returnsNormally);
    });
  });
}
