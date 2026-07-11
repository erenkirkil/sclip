import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Pre-parse defenses for SVG payloads, applied before anything is handed
/// to flutter_svg — both the `public.svg-image` UTI path and the
/// plain-text `<svg>...</svg>` path go through [isSafePayload].
abstract final class SvgSanitizer {
  /// Hard cap for SVG payloads. Real vector assets from Figma/Illustrator
  /// routinely run 3-6 MB; 20 MB is comfortably above that while still
  /// cutting off obviously-malicious oversize payloads cheaply. The primary
  /// defense against Billion-Laughs-style expansion is the DOCTYPE/ENTITY
  /// reject below — size alone is not a defense there (a <1 KB file can
  /// expand to gigabytes).
  static const maxSvgBytes = 20 * 1024 * 1024;

  /// Byte-level pre-parse check: reject SVG payloads that contain XXE /
  /// XInclude constructs. Scans the WHOLE payload case-insensitively — a
  /// fixed head window is bypassable (XML allows unbounded comments before
  /// the DOCTYPE, pushing it past any cutoff) and while XML mandates
  /// uppercase DOCTYPE/ENTITY, this guard is defense in depth and must not
  /// rely on the strictness of whatever parser sits behind flutter_svg in
  /// the future. `allowMalformed: true` so non-UTF-8 garbage decodes to
  /// replacement chars instead of throwing — we still reject it on content
  /// grounds downstream. False positives (an SVG whose *text content*
  /// mentions these tokens) merely demote the payload to a text entry.
  static bool isSafePayload(Uint8List bytes) {
    if (bytes.length > maxSvgBytes) return false;
    final body = utf8.decode(bytes, allowMalformed: true).toLowerCase();
    if (body.contains('<!doctype') ||
        body.contains('<!entity') ||
        body.contains('<!attlist')) {
      return false;
    }
    if (body.contains('xmlns:xi=') || body.contains('xinclude')) {
      return false;
    }
    return true;
  }

  /// Heuristic for "this plain-text payload is actually SVG markup". Trim
  /// + lowercase the head, allow an optional XML prolog, then require a
  /// `<svg` open tag and a `</svg>` close. Restrictive enough that we
  /// don't accidentally treat HTML snippets containing inline `<svg>`
  /// fragments as standalone SVG documents.
  static bool looksLikeSvgMarkup(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return false;
    final headLen = trimmed.length < 512 ? trimmed.length : 512;
    final head = trimmed.substring(0, headLen).toLowerCase();
    final body = trimmed.toLowerCase();
    final startsWithSvg =
        head.startsWith('<svg') ||
        head.startsWith('<?xml') && head.contains('<svg');
    return startsWithSvg && body.contains('</svg>');
  }
}
