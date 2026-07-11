/// Pasteboard format definitions and format↔extension mappings shared by
/// the classifier (reading) and the service's writeBack (writing).
library;

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_entry.dart';

/// SVG flavor. super_clipboard has no built-in SVG format; browsers and
/// design tools publish `public.svg-image` / `image/svg+xml`.
final svgFormat = SimpleFileFormat(
  uniformTypeIdentifiers: ['public.svg-image'],
  mimeTypes: ['image/svg+xml'],
);

/// RTF pasteboard flavor. Rich document editors (Word, Pages, TextEdit)
/// publish RTF alongside plain text when copying text, while
/// image/PDF-first sources (browsers, Preview, Finder) don't — so
/// plainText+RTF together identifies a "text copied from a rich editor"
/// payload. Formats.rtf can't be used here: on Windows it falls back to
/// the 'application/rtf' MIME name, but the actual registered clipboard
/// format is 'Rich Text Format'.
final rtfFormat = SimpleFileFormat(
  uniformTypeIdentifiers: ['public.rtf'],
  windowsFormats: ['Rich Text Format'],
  mimeTypes: ['text/rtf', 'application/rtf'],
);

FileFormat formatForImage(ClipboardImageFormat tag) => switch (tag) {
  .png => Formats.png,
  .jpeg => Formats.jpeg,
  .gif => Formats.gif,
  .webp => Formats.webp,
};

String extensionForImage(ClipboardImageFormat format) => switch (format) {
  .png => 'png',
  .jpeg => 'jpg',
  .gif => 'gif',
  .webp => 'webp',
};

ClipboardImageFormat imageFormatForExtension(String ext) => switch (ext) {
  'jpg' || 'jpeg' => ClipboardImageFormat.jpeg,
  'gif' => ClipboardImageFormat.gif,
  'webp' => ClipboardImageFormat.webp,
  _ => ClipboardImageFormat.png,
};

void addImageToItem(
  DataWriterItem item,
  Uint8List bytes,
  ClipboardImageFormat? format,
) {
  switch (format) {
    case .jpeg:
      item.add(Formats.jpeg(bytes));
    case .gif:
      item.add(Formats.gif(bytes));
    case .webp:
      item.add(Formats.webp(bytes));
    case .png:
    case null:
      item.add(Formats.png(bytes));
  }
}
