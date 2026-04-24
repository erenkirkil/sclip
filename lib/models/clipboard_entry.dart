import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum ClipboardEntryType { text, image, imageSet, url, files, color, svg }

enum ClipboardImageFormat { png, jpeg, gif, webp }

class ClipboardEntry {
  ClipboardEntry._({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.contentHash,
    this.text,
    this.imageBytes,
    this.imageFormat,
    this.imagesBytes,
    this.imagesFormats,
    this.uris,
    this.isSensitive = false,
  });

  final String id;
  final ClipboardEntryType type;
  final DateTime createdAt;
  final String? text;
  final Uint8List? imageBytes;
  final ClipboardImageFormat? imageFormat;
  /// Populated for [ClipboardEntryType.imageSet] — one entry per clipboard
  /// item when the user copies multiple images at once. For single-image
  /// entries this stays null and [imageBytes]/[imageFormat] are used.
  final List<Uint8List>? imagesBytes;
  final List<ClipboardImageFormat>? imagesFormats;
  final List<Uri>? uris;
  final bool isSensitive;

  /// Short SHA-256 fingerprint of the content. Used for dedup across the
  /// history and as the clipboard-service change-detection signature. Does
  /// NOT include createdAt/id, so two reads of the same content produce the
  /// same hash.
  final String contentHash;

  factory ClipboardEntry.text(String value, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.text,
      createdAt: DateTime.now(),
      text: value,
      isSensitive: isSensitive,
      contentHash: _hashText('t', value),
    );
  }

  factory ClipboardEntry.url(Uri uri, {bool isSensitive = false}) {
    final s = uri.toString();
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.url,
      createdAt: DateTime.now(),
      text: s,
      uris: [uri],
      isSensitive: isSensitive,
      contentHash: _hashText('u', s),
    );
  }

  factory ClipboardEntry.image(
    Uint8List bytes, {
    ClipboardImageFormat format = ClipboardImageFormat.png,
    bool isSensitive = false,
  }) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.image,
      createdAt: DateTime.now(),
      imageBytes: bytes,
      imageFormat: format,
      isSensitive: isSensitive,
      contentHash: _hashBytes('i', bytes),
    );
  }

  /// Groups multiple rasters copied together as a single history slot. The
  /// user picks one to paste via the tile's thumbnail strip; we never fan
  /// out into N history entries since one multi-select copy would then
  /// evict everything else.
  factory ClipboardEntry.imageSet(
    List<Uint8List> bytes, {
    List<ClipboardImageFormat>? formats,
    bool isSensitive = false,
  }) {
    assert(bytes.length >= 2, 'imageSet requires at least two images');
    final fmts = formats ??
        List.filled(bytes.length, ClipboardImageFormat.png);
    assert(
      fmts.length == bytes.length,
      'formats length must match bytes length',
    );
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.imageSet,
      createdAt: DateTime.now(),
      imagesBytes: List.unmodifiable(bytes),
      imagesFormats: List.unmodifiable(fmts),
      isSensitive: isSensitive,
      contentHash: _hashImageSet(bytes),
    );
  }

  factory ClipboardEntry.svg(String xml, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.svg,
      createdAt: DateTime.now(),
      text: xml,
      isSensitive: isSensitive,
      contentHash: _hashText('s', xml),
    );
  }

  factory ClipboardEntry.color(String hex, {bool isSensitive = false}) {
    final normalized = normalizeHexColor(hex);
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.color,
      createdAt: DateTime.now(),
      text: normalized,
      isSensitive: isSensitive,
      contentHash: _hashText('c', normalized),
    );
  }

  factory ClipboardEntry.files(List<Uri> files, {bool isSensitive = false}) {
    final joined = files.map((u) => u.toString()).join('|');
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.files,
      createdAt: DateTime.now(),
      uris: files,
      isSensitive: isSensitive,
      contentHash: _hashText('f', joined),
    );
  }

  /// Returns a fresh copy that keeps id + content + hash but updates
  /// createdAt. Used when the user taps an existing entry to re-copy it so
  /// the "just now" label reflects the latest action.
  ClipboardEntry touched() => ClipboardEntry._(
        id: id,
        type: type,
        createdAt: DateTime.now(),
        text: text,
        imageBytes: imageBytes,
        imageFormat: imageFormat,
        imagesBytes: imagesBytes,
        imagesFormats: imagesFormats,
        uris: uris,
        isSensitive: isSensitive,
        contentHash: contentHash,
      );

  String get preview {
    switch (type) {
      case ClipboardEntryType.text:
      case ClipboardEntryType.url:
        final t = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        return t.length > 120 ? '${t.substring(0, 120)}…' : t;
      case ClipboardEntryType.color:
        return text ?? '';
      case ClipboardEntryType.image:
        final fmt = imageFormat?.name.toUpperCase() ?? 'IMG';
        return '$fmt · ${_formatBytes(imageBytes?.lengthInBytes ?? 0)}';
      case ClipboardEntryType.imageSet:
        final count = imagesBytes?.length ?? 0;
        final total = imagesBytes?.fold<int>(
              0,
              (sum, b) => sum + b.lengthInBytes,
            ) ??
            0;
        return '$count resim · ${_formatBytes(total)}';
      case ClipboardEntryType.svg:
        final bytes = (text ?? '').length;
        return 'SVG · ${bytes}B';
      case ClipboardEntryType.files:
        final n = uris?.length ?? 0;
        if (n == 0) return 'Files';
        if (n == 1) return uris!.first.toFilePath();
        return '$n files';
    }
  }

  /// Compact human size for previews: KB under 1MB, MB with one decimal
  /// above (so a 1145KB set reads "1.1MB" instead of "1145KB").
  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${bytes ~/ 1024}KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)}MB';
  }

  static int _counter = 0;
  static String _newId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }

  /// 64-bit truncation of SHA-256 over `prefix:value`. Collision probability
  /// at history size 30 is negligible (~ 2.4e-15) and 16-char strings are
  /// cheap to compare / store.
  static String _hashText(String prefix, String value) {
    final bytes = utf8.encode('$prefix:$value');
    return '$prefix:${sha256.convert(bytes).toString().substring(0, 16)}';
  }

  static String _hashBytes(String prefix, Uint8List bytes) {
    final digest = sha256.convert(bytes).toString().substring(0, 16);
    return '$prefix:${bytes.length}:$digest';
  }

  /// Order-sensitive hash over the set — two copies of [A, B] collide, but
  /// [A, B] and [B, A] don't. That matches how users think about the
  /// clipboard (first image tends to be the "lead" selection).
  static String _hashImageSet(List<Uint8List> images) {
    final parts = images
        .map((b) {
          final d = sha256.convert(b).toString().substring(0, 16);
          return '${b.length}:$d';
        })
        .join('|');
    final combined =
        sha256.convert(utf8.encode(parts)).toString().substring(0, 16);
    return 'is:${images.length}:$combined';
  }

  static final RegExp _hexColorRe =
      RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
  static final RegExp _rgbColorRe = RegExp(
    r'^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*(?:,\s*(?:0|1|0?\.\d+)\s*)?\)$',
    caseSensitive: false,
  );

  /// Parses the stored color text into ARGB32. Returns null if not a color entry
  /// or cannot be parsed. Supports #RGB, #RRGGBB, #RRGGBBAA and rgb()/rgba().
  int? toArgb32() {
    if (type != ClipboardEntryType.color) return null;
    final raw = (text ?? '').trim();
    if (raw.isEmpty) return null;

    if (raw.startsWith('#')) {
      var hex = raw.substring(1);
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      if (hex.length == 6) {
        final v = int.tryParse(hex, radix: 16);
        return v == null ? null : 0xFF000000 | v;
      }
      if (hex.length == 8) {
        final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
        final a = int.tryParse(hex.substring(6), radix: 16);
        if (rgb == null || a == null) return null;
        return (a << 24) | rgb;
      }
      return null;
    }

    final rgb = RegExp(r'\d{1,3}|0?\.\d+').allMatches(raw).toList();
    if (rgb.length < 3) return null;
    final r = int.parse(rgb[0].group(0)!).clamp(0, 255);
    final g = int.parse(rgb[1].group(0)!).clamp(0, 255);
    final b = int.parse(rgb[2].group(0)!).clamp(0, 255);
    var a = 255;
    if (rgb.length >= 4) {
      final raw = rgb[3].group(0)!;
      final f = double.tryParse(raw) ?? 1.0;
      a = (f * 255).round().clamp(0, 255);
    }
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static bool looksLikeColor(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return _hexColorRe.hasMatch(v) || _rgbColorRe.hasMatch(v);
  }

  static String normalizeHexColor(String value) {
    var v = value.trim();
    if (_rgbColorRe.hasMatch(v)) return v.toLowerCase();
    if (!v.startsWith('#')) v = '#$v';
    return v.toLowerCase();
  }

  static bool looksLikeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains('\n')) return false;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme) return false;
    return parsed.scheme == 'http' ||
        parsed.scheme == 'https' ||
        parsed.scheme == 'ftp' ||
        parsed.scheme == 'mailto';
  }
}
