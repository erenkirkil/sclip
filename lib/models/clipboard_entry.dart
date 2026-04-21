import 'dart:typed_data';

enum ClipboardEntryType { text, image, url, files, color }

class ClipboardEntry {
  ClipboardEntry._({
    required this.id,
    required this.type,
    required this.createdAt,
    this.text,
    this.imageBytes,
    this.uris,
    this.isSensitive = false,
  });

  final String id;
  final ClipboardEntryType type;
  final DateTime createdAt;
  final String? text;
  final Uint8List? imageBytes;
  final List<Uri>? uris;
  final bool isSensitive;

  factory ClipboardEntry.text(String value, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.text,
      createdAt: DateTime.now(),
      text: value,
      isSensitive: isSensitive,
    );
  }

  factory ClipboardEntry.url(Uri uri, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.url,
      createdAt: DateTime.now(),
      text: uri.toString(),
      uris: [uri],
      isSensitive: isSensitive,
    );
  }

  factory ClipboardEntry.image(Uint8List bytes, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.image,
      createdAt: DateTime.now(),
      imageBytes: bytes,
      isSensitive: isSensitive,
    );
  }

  factory ClipboardEntry.color(String hex, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.color,
      createdAt: DateTime.now(),
      text: normalizeHexColor(hex),
      isSensitive: isSensitive,
    );
  }

  factory ClipboardEntry.files(List<Uri> files, {bool isSensitive = false}) {
    return ClipboardEntry._(
      id: _newId(),
      type: ClipboardEntryType.files,
      createdAt: DateTime.now(),
      uris: files,
      isSensitive: isSensitive,
    );
  }

  String get preview {
    switch (type) {
      case ClipboardEntryType.text:
      case ClipboardEntryType.url:
        final t = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        return t.length > 120 ? '${t.substring(0, 120)}…' : t;
      case ClipboardEntryType.color:
        return text ?? '';
      case ClipboardEntryType.image:
        final kb = (imageBytes?.lengthInBytes ?? 0) ~/ 1024;
        return 'Image · ${kb}KB';
      case ClipboardEntryType.files:
        final n = uris?.length ?? 0;
        if (n == 0) return 'Files';
        if (n == 1) return uris!.first.toFilePath();
        return '$n files';
    }
  }

  static int _counter = 0;
  static String _newId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
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
