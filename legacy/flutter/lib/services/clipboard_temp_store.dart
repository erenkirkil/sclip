import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/clipboard_entry.dart';
import 'clipboard_formats.dart';

/// The single owner of `<tempDir>/sclip/` — the documented RAM-only
/// exception (docs/security.md, Risk 6). writeBack materializes SVG/PDF
/// bytes and imageSet files here so file-handler paste targets (Telegram,
/// Slack, Mail, Finder) work; the macOS native readFiles promise
/// resolution writes to the same root. Cleanup is layered: per-entry on
/// history eviction, [pruneAll] on graceful shutdown, and [pruneAll] again
/// on next start (crash recovery).
abstract final class ClipboardTempStore {
  /// Writes [bytes] to `<tempDir>/sclip/<entryId>/clipboard.<ext>` and
  /// returns the file URI, or null if the temp dir is unavailable. Stale
  /// files from a prior writeBack on the same entry are pruned first to
  /// keep the temp dir bounded.
  static Future<Uri?> materializeBytes(
    String entryId,
    List<int> bytes,
    String extension,
  ) async {
    try {
      final dir = await _freshEntryDir(entryId);
      final file = File('${dir.path}/clipboard.$extension');
      file.writeAsBytesSync(bytes);
      return file.uri;
    } catch (e) {
      debugPrint('sclip: temp materialize failed: $e');
      return null;
    }
  }

  /// Writes each image in [bytes] to a temp file under
  /// `<tempDir>/sclip/<entryId>/` and returns the absolute file paths.
  /// The paths are then handed to the native writeFiles bridge so
  /// Finder / Explorer get a paste-able CF_HDROP / NSURL companion
  /// alongside the modern public.file-url payload.
  static Future<List<String>> materializeImageSet(
    String entryId,
    List<Uint8List> bytes, {
    List<ClipboardImageFormat>? formats,
  }) async {
    try {
      final dir = await _freshEntryDir(entryId);
      final paths = <String>[];
      for (var i = 0; i < bytes.length; i++) {
        final fmt = (formats != null && i < formats.length)
            ? formats[i]
            : ClipboardImageFormat.png;
        final ext = extensionForImage(fmt);
        // Prefix numerically so target apps that sort by name keep the
        // original order of the set (1.png before 10.png thanks to padding).
        final name = '${(i + 1).toString().padLeft(3, '0')}.$ext';
        final file = File('${dir.path}/$name');
        file.writeAsBytesSync(bytes[i]);
        paths.add(file.path);
      }
      return paths;
    } catch (e) {
      debugPrint('sclip: paste-all temp materialize failed: $e');
      return const [];
    }
  }

  /// Deletes one entry's materialized directory (history eviction path).
  static Future<void> deleteEntry(String entryId) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/sclip/$entryId');
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (e) {
      debugPrint('sclip: entry temp cleanup failed: $e');
    }
  }

  /// Wipes the whole `<tempDir>/sclip/` root. Per-entry SVG/PDF/imageSet
  /// dirs and the native readFiles destination all live under it, so a
  /// single recursive delete is enough. Best-effort: any failure
  /// (permissions, locked file) is logged but never blocks the caller.
  static Future<void> pruneAll() async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/sclip');
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (e) {
      debugPrint('sclip: temp dir prune failed: $e');
    }
  }

  /// Returns `<tempDir>/sclip/<entryId>/`, recreated empty.
  static Future<Directory> _freshEntryDir(String entryId) async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/sclip/$entryId');
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // ignore — we'll overwrite files individually below
      }
    }
    dir.createSync(recursive: true);
    return dir;
  }
}
