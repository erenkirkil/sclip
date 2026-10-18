import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_entry.dart';
import 'clipboard_formats.dart';
import 'svg_sanitizer.dart';

/// Turns raw pasteboard contents into the richest [ClipboardEntry] we can
/// build — the format-priority brain of the service. Stateless; the
/// service owns polling, dedup and write-back.
final class ClipboardClassifier {
  const ClipboardClassifier();

  /// Per-entry cap for PDF payloads. 25 MB covers the vast majority of
  /// pasted documents (academic papers, invoices, reports) without letting
  /// a single oversized payload balloon RAM. PDFs also count toward the
  /// history layer's total-bytes budget, so a PDF flood evicts older heavy
  /// entries instead of accumulating.
  static const maxPdfBytes = 25 * 1024 * 1024;

  /// Per-entry cap for plain/HTML text, in UTF-16 code units (≈ bytes for
  /// ASCII). Text was the only content type without an ingest cap — a
  /// select-all copy of a huge log or JSON otherwise lands wholesale in
  /// the heap (twice over for richText). Oversized payloads are dropped,
  /// not truncated: pasting silently-corrupted content would be worse
  /// than having no history entry, and the OS clipboard still carries
  /// the full payload for a direct Cmd/Ctrl+V.
  static const maxTextChars = 2 * 1024 * 1024;

  /// Watchdog for the async super_clipboard read callbacks. If a callback
  /// never fires (decode error routed past us, wedged native read), the
  /// pending completer would otherwise never resolve — the service's tick
  /// guard wouldn't reset, and monitoring would silently die until app
  /// restart. Ten seconds is generous for a local IPC read.
  static const _readTimeout = Duration(seconds: 10);

  /// Filename extensions we recognise as raster images. Drives the
  /// "Finder copy of N PNGs becomes an imageSet" path. Sniffing magic
  /// bytes would catch mislabeled files but adds disk reads on every
  /// files-on-clipboard tick; extension is reliable enough for the shells
  /// that publish CF_HDROP / NSURL (Finder, Explorer, Photos).
  static const _imageFileExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp'};

  /// Size guard for the file → image conversion, applied both per file and
  /// to the running TOTAL of the set. Mirrors the HistoryProvider default
  /// `maxImageBytes` (5 MiB), which caps the imageSet *total* — checking
  /// only per-file here would burn I/O and hashing on a set the history
  /// layer silently drops (e.g. two 3 MB PNGs).
  static const _maxImageInjectBytes = 5 * 1024 * 1024;

  /// Priority for collapsing a mixed multi-item payload to its richest
  /// single entry — mirrors the per-item probe order.
  static const _richness = {
    ClipboardEntryType.image: 6,
    ClipboardEntryType.svg: 5,
    ClipboardEntryType.pdf: 4,
    ClipboardEntryType.richText: 3,
    ClipboardEntryType.url: 2,
    ClipboardEntryType.color: 1,
    ClipboardEntryType.text: 0,
  };

  /// Classifies a full [ClipboardReader]. The all-images fast path
  /// (multi-screenshot, design exports) becomes a single imageSet so the
  /// grid UI lights up. Anything else multi-item collapses to the richest
  /// single classified entry — heterogeneous super_clipboard payloads
  /// (e.g. Figma's "image + text" pair) are vanishingly rare in practice
  /// and storing a hybrid record the UI can't render usefully isn't worth
  /// the architectural weight. The user can always re-copy the other half.
  Future<ClipboardEntry?> read(ClipboardReader reader) async {
    final classified = <ClipboardEntry>[];
    for (final item in reader.items) {
      final c = await classifyItem(item);
      if (c != null) classified.add(c);
    }
    if (classified.isEmpty) return null;
    if (classified.length == 1) return classified.first;

    if (classified.every((e) => e.type == ClipboardEntryType.image)) {
      // HistoryProvider caps the imageSet TOTAL at its image cap; a set
      // over the limit would be silently dropped there. Collapsing to the
      // first image that fits keeps *something* in history instead.
      final total = classified.fold<int>(
        0,
        (s, e) => s + e.imageBytes!.lengthInBytes,
      );
      if (total > _maxImageInjectBytes) {
        for (final e in classified) {
          if (e.imageBytes!.lengthInBytes <= _maxImageInjectBytes) return e;
        }
        return classified.first;
      }
      return ClipboardEntry.imageSet(
        [for (final e in classified) e.imageBytes!],
        formats: [
          for (final e in classified) e.imageFormat ?? ClipboardImageFormat.png,
        ],
      );
    }

    // Mixed payload: pick the richest single entry. Stable sort keeps
    // original copy order as the tiebreaker.
    classified.sort(
      (a, b) => (_richness[b.type] ?? 0).compareTo(_richness[a.type] ?? 0),
    );
    return classified.first;
  }

  /// Probes a single pasteboard item in priority order and returns the
  /// richest [ClipboardEntry] representation we can build. Returns null if
  /// nothing recognized — file URIs are intentionally skipped here
  /// (NSFilePromise resolution would empty the source app's clipboard; the
  /// service's files path handles those via the native channel).
  Future<ClipboardEntry?> classifyItem(ClipboardDataReader item) async {
    final hasPlain = item.canProvide(Formats.plainText);
    // Office/Word (and other rich editors) publish a PDF — and sometimes a
    // raster — *render* of the selection alongside plain/RTF/HTML text so
    // targets can paste with full fidelity. Without this gate the PDF
    // flavor outranks the text and a plain Word sentence becomes a pdf
    // entry. plainText+RTF together is the signature of "text copied from
    // a rich editor"; image-first sources (browsers, screenshot tools)
    // don't publish RTF, so their image flavor still wins below.
    final isRichDocTextCopy = hasPlain && item.canProvide(rtfFormat);

    // Binary probes (image → svg → pdf). [allowPdfWithText] is false on
    // the primary pass — a PDF flavor next to a plain-text flavor is a
    // fidelity companion, not the payload — and true on the fallback pass
    // where the advertised text legs turned out to be empty.
    Future<ClipboardEntry?> probeBinary({
      required bool allowPdfWithText,
    }) async {
      for (final tag in ClipboardImageFormat.values) {
        final format = formatForImage(tag);
        if (!item.canProvide(format)) continue;
        final bytes = await _readBinary(item, format);
        if (bytes != null && bytes.isNotEmpty) {
          return ClipboardEntry.image(bytes, format: tag);
        }
      }

      if (item.canProvide(svgFormat)) {
        final bytes = await _readBinary(item, svgFormat);
        if (bytes != null &&
            bytes.isNotEmpty &&
            SvgSanitizer.isSafePayload(bytes)) {
          try {
            return ClipboardEntry.svg(utf8.decode(bytes));
          } catch (_) {
            // Non-UTF-8 payload — skip SVG
          }
        }
      }

      if ((allowPdfWithText || !hasPlain) && item.canProvide(Formats.pdf)) {
        final bytes = await _readBinary(item, Formats.pdf);
        if (bytes != null && bytes.isNotEmpty) {
          if (bytes.length > maxPdfBytes) {
            debugPrint(
              'sclip: dropping oversized PDF payload '
              '(${bytes.length} bytes > $maxPdfBytes)',
            );
          } else {
            return ClipboardEntry.pdf(bytes);
          }
        }
      }
      return null;
    }

    if (!isRichDocTextCopy) {
      final binary = await probeBinary(allowPdfWithText: false);
      if (binary != null) return binary;
    }

    if (hasPlain) {
      final text = await _readText(item, Formats.plainText);
      if (text != null && text.length > maxTextChars) {
        debugPrint(
          'sclip: dropping oversized text payload '
          '(${text.length} chars > $maxTextChars)',
        );
        return null;
      }
      if (text != null && text.isNotEmpty) {
        // URL/color detection takes priority over richText even when HTML is
        // also published: copying a bare URL from a browser typically
        // includes a `<a>` wrapper, but the user wants the URL UI (Open
        // button) rather than a styled snippet.
        if (ClipboardEntry.looksLikeUrl(text)) {
          return ClipboardEntry.url(Uri.parse(text.trim()));
        }
        if (ClipboardEntry.looksLikeColor(text)) {
          return ClipboardEntry.color(text);
        }
        // Bare emails / international phone numbers get the url entry's
        // "Aç" action (mailto:/tel:) while the tile and any re-paste keep
        // the text exactly as copied (displayText).
        if (ClipboardEntry.looksLikeEmail(text)) {
          final bare = text.trim();
          return ClipboardEntry.url(
            Uri.parse('mailto:$bare'),
            displayText: bare,
          );
        }
        if (ClipboardEntry.looksLikePhone(text)) {
          final bare = text.trim();
          return ClipboardEntry.url(
            Uri.parse('tel:${ClipboardEntry.normalizePhone(bare)}'),
            displayText: bare,
          );
        }
        // SVG XML pasted as plain text (browser "View Source" copy, code
        // editors) doesn't carry the public.svg-image UTI, so the binary
        // SVG branch above misses it. Recognise the markup directly so the
        // tile still renders the SVG and writeBack publishes it as a file
        // for paste-into-Telegram fidelity. Same XXE guard as the binary
        // path — the sanitizer is the only thing standing between us and
        // a malicious payload here.
        if (SvgSanitizer.looksLikeSvgMarkup(text)) {
          // utf8.encode already returns Uint8List since Dart 3 — a
          // fromList wrapper would copy up to 20MB (SVG cap) for nothing.
          final bytes = utf8.encode(text);
          if (SvgSanitizer.isSafePayload(bytes)) {
            return ClipboardEntry.svg(text);
          }
        }
        if (item.canProvide(Formats.htmlText)) {
          final html = await _readText(item, Formats.htmlText);
          // Oversized HTML degrades to a plain-text entry rather than
          // dropping the copy — the text leg is the payload the user
          // actually selected; the markup is a fidelity bonus.
          if (html != null &&
              html.isNotEmpty &&
              html != text &&
              html.length <= maxTextChars) {
            return ClipboardEntry.richText(
              plainText: text,
              html: html,
              rtfBytes: await _readRtfCompanion(item),
            );
          }
        }
        return ClipboardEntry.text(text);
      }
    }

    // Edge case: HTML payload with no plain-text companion (some web apps
    // skip the plainText leg). Strip tags for the searchable preview so
    // dedup and the tile title still work; original markup is preserved
    // for writeBack.
    if (item.canProvide(Formats.htmlText)) {
      final html = await _readText(item, Formats.htmlText);
      if (html != null && html.isNotEmpty && html.length <= maxTextChars) {
        final stripped = html
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (stripped.isNotEmpty) {
          return ClipboardEntry.richText(
            plainText: stripped,
            html: html,
            rtfBytes: await _readRtfCompanion(item),
          );
        }
      }
    }

    // Rich-doc gate engaged but every advertised text leg came back empty —
    // e.g. copying an image *object* inside Word still publishes RTF. Fall
    // back to the binary probes so the payload isn't lost; PDF is allowed
    // here because text demonstrably wasn't the payload.
    if (isRichDocTextCopy) {
      return probeBinary(allowPdfWithText: true);
    }

    return null;
  }

  /// Builds the richest entry for a list of file paths. When every path
  /// looks like a raster image and each file fits the per-image cap,
  /// reads bytes and returns an image / imageSet so the grid UI lights
  /// up. Falls back to a files entry for mixed or non-image content,
  /// oversized files, or read failures — the user still sees the file
  /// list and can paste it. Reads are sequential to avoid hammering the
  /// disk when a user has just dropped 30+ files on the clipboard.
  Future<ClipboardEntry> entryForFilePaths(List<String> paths) async {
    ClipboardEntry filesFallback() =>
        ClipboardEntry.files([for (final p in paths) Uri.file(p)]);
    final formats = <ClipboardImageFormat>[];
    for (final p in paths) {
      final ext = _extensionOfPath(p);
      if (!_imageFileExtensions.contains(ext)) {
        return filesFallback();
      }
      formats.add(imageFormatForExtension(ext));
    }
    final bytesList = <Uint8List>[];
    var totalBytes = 0;
    for (final p in paths) {
      try {
        final f = File(p);
        // Sync stat: metadata lookup is microseconds and the async dart:io
        // variant round-trips the IO event loop per file
        // (avoid_slow_async_io).
        final stat = f.statSync();
        if (stat.size <= 0 || stat.size > _maxImageInjectBytes) {
          return filesFallback();
        }
        // Bail to the files fallback BEFORE reading bytes the history
        // layer's set-total cap would silently drop — the user still sees
        // the file list and can paste it.
        totalBytes += stat.size;
        if (totalBytes > _maxImageInjectBytes) {
          return filesFallback();
        }
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) return filesFallback();
        bytesList.add(bytes);
      } catch (e) {
        debugPrint('sclip: image-from-file read failed for $p: $e');
        return filesFallback();
      }
    }
    if (bytesList.length == 1) {
      return ClipboardEntry.image(bytesList.first, format: formats.first);
    }
    return ClipboardEntry.imageSet(bytesList, formats: formats);
  }

  /// Lowercase extension after the final `.` in the basename. Walks back
  /// to the last `/` or `\` so a directory like `/foo.bar/baz` doesn't
  /// produce a phantom `bar` extension. Returns empty when the file is a
  /// dotfile or has no extension at all.
  static String _extensionOfPath(String path) {
    final lastSep = path.lastIndexOf(RegExp(r'[/\\]'));
    final filename = lastSep >= 0 ? path.substring(lastSep + 1) : path;
    final dot = filename.lastIndexOf('.');
    if (dot <= 0) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  /// Reads the RTF flavor when the item advertises one, capped at the
  /// same per-entry limit as text/HTML. Returns null (drop the companion,
  /// keep the entry) on absence or oversize — RTF is a paste-fidelity
  /// bonus for Word/Pages-style targets, never the payload itself.
  Future<Uint8List?> _readRtfCompanion(ClipboardDataReader item) async {
    if (!item.canProvide(rtfFormat)) return null;
    final bytes = await _readBinary(item, rtfFormat);
    if (bytes == null || bytes.isEmpty || bytes.length > maxTextChars) {
      return null;
    }
    return bytes;
  }

  Future<String?> _readText(DataReader reader, ValueFormat<String> format) {
    final completer = Completer<String?>();
    final progress = reader.getValue<String>(
      format,
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      // Without onError, a decode failure (e.g. malformed CF_HTML offsets
      // on Windows) goes to the zone handler and onValue never fires —
      // the exact wedge the watchdog exists for. Handle it directly.
      onError: (e) {
        debugPrint('sclip: text read errored for ${format.runtimeType}: $e');
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    // Null progress means the value is unavailable and the callback will
    // never be invoked (per super_clipboard docs) — resolve immediately.
    if (progress == null && !completer.isCompleted) completer.complete(null);
    return completer.future.timeout(_readTimeout, onTimeout: () => null);
  }

  Future<Uint8List?> _readBinary(DataReader reader, FileFormat format) {
    final completer = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          if (!completer.isCompleted) completer.complete(bytes);
        } catch (e) {
          debugPrint('sclip: binary read failed for ${format.runtimeType}: $e');
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (e) {
        debugPrint('sclip: binary read errored: $e');
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null && !completer.isCompleted) completer.complete(null);
    return completer.future.timeout(_readTimeout, onTimeout: () => null);
  }
}
