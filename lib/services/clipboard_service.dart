import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_entry.dart';
import 'clipboard_classifier.dart';
import 'clipboard_formats.dart';
import 'clipboard_temp_store.dart';

typedef ClipboardReaderFactory = Future<ClipboardReader?> Function();
typedef ClipboardEntryReader = Future<ClipboardEntry?> Function();

/// Returns the list of file paths currently on the clipboard, or an empty
/// list when nothing was readable. macOS resolves NSFilePromise items into
/// a temp dir and republishes resolved URLs to keep the source clipboard
/// usable; Windows simply walks CF_HDROP. A missing native handler returns
/// an empty list so the Dart side can treat "couldn't read" the same as
/// "nothing to read".
typedef FilesReader = Future<List<String>> Function();

/// Snapshot returned by the native `currentState` channel: a monotonic
/// change counter (macOS NSPasteboard.changeCount / Windows
/// GetClipboardSequenceNumber), a sensitive-content flag, and a hasFiles
/// flag that flips on for any "files-on-clipboard" payload (NSURL or
/// NSFilePromise on macOS, CF_HDROP on Windows). When hasFiles is set the
/// Dart side dispatches `readFiles` on the native channel instead of
/// running super_clipboard, which would either fail to read the payload
/// or, on macOS, destructively resolve a promise. A missing native
/// handler is expressed as [ClipboardState.unavailable].
@immutable
class ClipboardState {
  const ClipboardState({
    required this.change,
    required this.sensitive,
    this.hasFiles = false,
  });

  static const unavailable = ClipboardState(change: -1, sensitive: false);

  final int change;
  final bool sensitive;
  final bool hasFiles;
}

typedef ClipboardStateProbe = Future<ClipboardState> Function();

/// Owns the poll loop, dedup state and clipboard write-back. Format
/// classification lives in [ClipboardClassifier]; temp-file
/// materialization in [ClipboardTempStore]; SVG defenses in SvgSanitizer.
class ClipboardService {
  ClipboardService({
    Duration interval = const Duration(milliseconds: 500),
    this.sensitiveFilterEnabled = true,
    ClipboardReaderFactory? readerFactory,
    ClipboardEntryReader? entryReader,
    ClipboardStateProbe? stateProbe,
    FilesReader? filesReader,
  }) : _interval = interval,
       _readerFactory = readerFactory ?? _defaultReader,
       _entryReaderOverride = entryReader,
       _stateProbe = stateProbe ?? _defaultStateProbe,
       _filesReader = filesReader ?? _defaultFilesReader;

  static const _metaChannel = MethodChannel('sclip/clipboard');
  static const _classifier = ClipboardClassifier();

  Duration _interval;
  Duration get interval => _interval;

  /// Re-arms the periodic timer with a new cadence. No-op while stopped —
  /// the next [start] will honour the new value. Called from the settings
  /// page when the user switches polling rate.
  set interval(Duration value) {
    if (value == _interval) return;
    _interval = value;
    if (_timer != null) {
      _timer!.cancel();
      _timer = Timer.periodic(_interval, (_) => _tick());
    }
  }

  /// Flipped at runtime from the settings page. When false, concealed-type
  /// payloads (password managers) still enter history; the risk is on the
  /// user at that point.
  bool sensitiveFilterEnabled;
  final ClipboardReaderFactory _readerFactory;
  final ClipboardEntryReader? _entryReaderOverride;
  final ClipboardStateProbe _stateProbe;
  final FilesReader _filesReader;
  final StreamController<ClipboardEntry> _controller =
      StreamController<ClipboardEntry>.broadcast();

  Timer? _timer;

  /// Last seen native change counter. -1 means "not yet observed". When this
  /// matches the current native value, we skip the tick entirely — no read,
  /// no super_clipboard call — so idle CPU stays near zero.
  int _lastChange = -1;

  /// Content fingerprint of the most recently observed entry. Lets us
  /// ignore our own writeBack (the OS change counter bumps on every write,
  /// including ours).
  String? _lastSignature;

  bool _ticking = false;
  bool _primed = false;

  Stream<ClipboardEntry> get entries => _controller.stream;
  bool get isRunning => _timer != null;

  /// Rewrites the OS clipboard with [entry]'s content. For
  /// [ClipboardEntryType.imageSet]: when [imageIndex] is null, every image
  /// in the set is written as its own clipboard item (multi-item payload);
  /// when provided, only that single image is written so a plain Cmd/Ctrl+V
  /// into an app that only accepts one item still gets the intended image.
  ///
  /// [plainOnly] publishes ONLY the plain-text representation — the
  /// classic "paste as plain text": a richText entry loses its markup, an
  /// SVG pastes as raw XML. Entries without a text representation
  /// (image/pdf/files) fall through to the full-fidelity path.
  Future<void> writeBack(
    ClipboardEntry entry, {
    int? imageIndex,
    bool plainOnly = false,
  }) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    if (plainOnly) {
      final value = entry.text ?? '';
      if (value.isNotEmpty) {
        final plainItem = DataWriterItem()..add(Formats.plainText(value));
        await clipboard.write([plainItem]);
        // The published payload IS a plain-text entry now — sign it as
        // such so the next tick's dedup suppresses self-ingestion (the
        // entry's own hash covers its full-fidelity representation).
        _lastSignature = ClipboardEntry.text(value).contentHash;
        await _captureWriteChange();
        return;
      }
      // No text representation — full fidelity is the only option.
    }

    final item = DataWriterItem();
    switch (entry.type) {
      case .text:
      case .url:
      case .color:
        final value = entry.text ?? '';
        if (value.isEmpty) return;
        item.add(Formats.plainText(value));
        break;
      case .svg:
        final xml = entry.text ?? '';
        if (xml.isEmpty) return;
        final bytes = utf8.encode(xml);
        // File-handler targets (Telegram, Slack, Mail attachments) don't
        // recognize the public.svg-image UTI as a paste type — they fall
        // back to plainText and drop raw XML into the chat. Publishing a
        // file URI alongside the SVG bytes lets those apps treat it as an
        // attachment, while apps that DO know the UTI (browsers, Figma)
        // still pick the inline bytes. plainText stays as the universal
        // fallback. All three on a single item so target picks one.
        final fileUri = await _materializeBytesAsFile(entry, bytes, 'svg');
        if (fileUri != null) {
          item.add(Formats.fileUri(fileUri));
        }
        item.add(svgFormat(bytes));
        item.add(Formats.plainText(xml));
        break;
      case .image:
        final bytes = entry.imageBytes;
        if (bytes == null || bytes.isEmpty) return;
        addImageToItem(item, bytes, entry.imageFormat);
        break;
      case .imageSet:
        final bytes = entry.imagesBytes;
        final formats = entry.imagesFormats;
        if (bytes == null || bytes.isEmpty) return;
        if (imageIndex == null) {
          await _writeBackImageSetAll(clipboard, entry, bytes, formats);
          return;
        }
        final i = imageIndex.clamp(0, bytes.length - 1);
        final fmt = (formats != null && i < formats.length)
            ? formats[i]
            : ClipboardImageFormat.png;
        addImageToItem(item, bytes[i], fmt);
        await clipboard.write([item]);
        // Track the single-image signature we just wrote so the next tick
        // doesn't re-ingest it as a brand-new clipboard entry.
        _lastSignature = ClipboardEntry.image(
          bytes[i],
          format: fmt,
        ).contentHash;
        await _captureWriteChange();
        return;
      case .files:
        final uris = entry.uris;
        if (uris == null || uris.isEmpty) return;
        final paths = [
          for (final uri in uris)
            if (uri.isScheme('file')) uri.toFilePath(),
        ];
        if (paths.isEmpty) return;
        // Native writeFiles is the authoritative route — it sets the
        // legacy companions (NSFilenamesPboardType / CF_HDROP) that
        // Finder and Explorer require for their paste menus to activate.
        // super_clipboard's Formats.fileUri alone publishes
        // public.file-url but those shells silently ignore it. Fall back
        // to super_clipboard only when the native handler is missing
        // (test environment or an outdated bundle).
        final wroteNatively = await _writeFilesNative(paths);
        if (!wroteNatively) {
          final items = uris
              .map((uri) => DataWriterItem()..add(Formats.fileUri(uri)))
              .toList();
          await clipboard.write(items);
        }
        _lastSignature = entry.contentHash;
        await _captureWriteChange();
        return;
      case .pdf:
        final bytes = entry.pdfBytes;
        if (bytes == null || bytes.isEmpty) return;
        // Same dual-publish trick as SVG: many file-handler targets (Mail,
        // Slack, Telegram) only attach the PDF when they see a file URI;
        // apps that handle the com.adobe.pdf UTI directly (Preview, browsers)
        // still pick up the inline bytes.
        final fileUri = await _materializeBytesAsFile(entry, bytes, 'pdf');
        if (fileUri != null) {
          item.add(Formats.fileUri(fileUri));
        }
        item.add(Formats.pdf(bytes));
        break;
      case .richText:
        final plain = entry.text ?? '';
        final html = entry.richTextHtml ?? '';
        if (plain.isEmpty && html.isEmpty) return;
        // plainText must be present alongside htmlText: super_clipboard's
        // own docs warn that some platforms (notably Android) silently drop
        // the htmlText payload when plainText is missing.
        if (plain.isNotEmpty) {
          item.add(Formats.plainText(plain));
        }
        if (html.isNotEmpty) {
          item.add(Formats.htmlText(html));
        }
        // RTF companion (when the source published one): RTF-first
        // targets — Word, Pages, older editors — paste with native
        // fidelity instead of converting from HTML.
        final rtf = entry.rtfBytes;
        if (rtf != null && rtf.isNotEmpty) {
          item.add(rtfFormat(rtf));
        }
        break;
    }
    await clipboard.write([item]);
    _lastSignature = entry.contentHash;
    await _captureWriteChange();
  }

  /// Paste-all for an imageSet. Sensitive entries publish inline
  /// multi-item image data (never touching the disk); everything else goes
  /// through temp files + the native CF_HDROP / NSURL path so Finder /
  /// Explorer light up alongside file-handler apps (Telegram, Slack,
  /// Mail). Multi-item image payloads get silently collapsed to the first
  /// item by most target apps under Cmd/Ctrl+V; file URIs are treated as
  /// attachments and actually come through as a set. Users who want a
  /// single inline image still have the per-thumbnail paste path. The next
  /// tick will re-read the temp files and rebuild the same imageSet
  /// (identical bytes ⇒ identical hash), so dedup against
  /// entry.contentHash suppresses the self-ingestion.
  Future<void> _writeBackImageSetAll(
    SystemClipboard clipboard,
    ClipboardEntry entry,
    List<Uint8List> bytes,
    List<ClipboardImageFormat>? formats,
  ) async {
    if (entry.isSensitive) {
      final items = <DataWriterItem>[];
      for (var i = 0; i < bytes.length; i++) {
        final fmt = (formats != null && i < formats.length)
            ? formats[i]
            : ClipboardImageFormat.png;
        final it = DataWriterItem();
        addImageToItem(it, bytes[i], fmt);
        items.add(it);
      }
      await clipboard.write(items);
      _lastSignature = entry.contentHash;
      await _captureWriteChange();
      return;
    }

    final paths = await ClipboardTempStore.materializeImageSet(
      entry.id,
      bytes,
      formats: formats,
    );
    if (paths.isEmpty) return;
    final wroteNatively = await _writeFilesNative(paths);
    if (!wroteNatively) {
      final items = paths
          .map((p) => DataWriterItem()..add(Formats.fileUri(File(p).uri)))
          .toList();
      await clipboard.write(items);
    }
    _lastSignature = entry.contentHash;
    await _captureWriteChange();
  }

  /// Probes the OS clipboard immediately after our own write so we can
  /// fast-forward `_lastChange`. This prevents the next `_tick` from
  /// reading the clipboard entirely, which solves a macOS edge case where
  /// `NSPasteboard` slightly modifies HTML/RTF payloads upon write.
  /// Without this, the modified payload produces a different `contentHash`
  /// on read, causing our own write to be incorrectly ingested as a
  /// duplicate.
  Future<void> _captureWriteChange() async {
    try {
      final state = await _stateProbe();
      if (state.change != -1) {
        _lastChange = state.change;
      }
    } catch (e) {
      debugPrint('sclip: failed to capture write change: $e');
    }
  }

  /// Temp materialization with the sensitive-content guard: sensitive
  /// content must never be written to disk — the file URI leg is a
  /// fidelity bonus, not a requirement; targets fall back to the inline
  /// bytes / plainText legs published alongside it.
  Future<Uri?> _materializeBytesAsFile(
    ClipboardEntry entry,
    List<int> bytes,
    String extension,
  ) async {
    if (entry.isSensitive) return null;
    return ClipboardTempStore.materializeBytes(entry.id, bytes, extension);
  }

  /// Calls the native `writeFiles` bridge with [paths]. Returns true on
  /// success, false when the platform handler is missing (test bench or
  /// outdated bundle) or any error bubbles up — the caller falls back to
  /// the super_clipboard route in those cases. Empty input is treated as
  /// a no-op so a misdispatched call can't wipe the user's clipboard.
  Future<bool> _writeFilesNative(List<String> paths) async {
    if (paths.isEmpty) return false;
    try {
      await _metaChannel.invokeMethod<void>('writeFiles', {'paths': paths});
      return true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('sclip: writeFiles native dispatch failed: $e');
      return false;
    }
  }

  static Future<ClipboardReader?> _defaultReader() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    return clipboard.read();
  }

  static Future<ClipboardState> _defaultStateProbe() async {
    try {
      final v = await _metaChannel.invokeMapMethod<String, dynamic>(
        'currentState',
      );
      if (v == null) return ClipboardState.unavailable;
      return ClipboardState(
        change: (v['change'] as int?) ?? -1,
        sensitive: (v['sensitive'] as bool?) ?? false,
        hasFiles: (v['hasFiles'] as bool?) ?? false,
      );
    } on MissingPluginException {
      return ClipboardState.unavailable;
    } catch (e) {
      debugPrint('sclip: clipboard state probe failed: $e');
      return ClipboardState.unavailable;
    }
  }

  /// Default native dispatch for `readFiles`. Returns a list of absolute
  /// file paths the OS handed back. Empty list is the only failure mode
  /// callers should handle — platform exceptions and missing handlers
  /// collapse to that so the tick can fall through cleanly.
  static Future<List<String>> _defaultFilesReader() async {
    try {
      final v = await _metaChannel.invokeListMethod<dynamic>('readFiles');
      if (v == null) return const [];
      return [
        for (final p in v)
          if (p is String && p.isNotEmpty) p,
      ];
    } on MissingPluginException {
      return const [];
    } catch (e) {
      debugPrint('sclip: files reader failed: $e');
      return const [];
    }
  }

  void start() {
    if (_timer != null) return;
    // Wipe any leftover temp files from a prior run so the working set
    // can't grow across restarts — this is also the crash-recovery leg of
    // the temp-store cleanup (dispose handles graceful shutdown).
    unawaited(ClipboardTempStore.pruneAll());
    _timer = Timer.periodic(_interval, (_) => _tick());
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
    // Sweep materialized temp files on graceful shutdown — without this,
    // pasted SVG/PDF/imageSet content would sit on disk until the NEXT
    // launch's start() prune.
    await ClipboardTempStore.pruneAll();
  }

  /// Deletes the per-entry temp directory created by writeBack
  /// materialization once [entry] permanently leaves the history. Skipped
  /// while the entry's content is still our most recent clipboard write:
  /// the OS clipboard may reference the file URIs, and the imageSet
  /// paste-all dedup re-reads those files on the next tick. Such leftovers
  /// are swept by the prune in [dispose] / [start] instead.
  Future<void> cleanupEntryTempFiles(ClipboardEntry entry) async {
    if (entry.contentHash == _lastSignature) return;
    await ClipboardTempStore.deleteEntry(entry.id);
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      // Step 1 — cheap native probe. If the change counter hasn't moved,
      // the clipboard hasn't been touched since our last tick, so we skip
      // all work (no IPC to super_clipboard, no decoding, no allocations).
      final state = await _stateProbe();
      final previousChange = _lastChange;
      if (state.change != -1) {
        if (state.change == _lastChange) return;
        _lastChange = state.change;
      }

      // Step 2 — sensitive check. Password-manager payloads advertise a
      // concealed type; skip the read entirely so secrets never enter the
      // Dart heap. _lastSignature is intentionally left untouched so the
      // next non-sensitive copy still counts as "new". The filter can be
      // disabled from settings for users who knowingly accept the risk.
      if (state.sensitive && sensitiveFilterEnabled) return;

      // Step 2b — files dispatch. NSURL / NSFilePromise on macOS and
      // CF_HDROP on Windows surface here. We bypass super_clipboard
      // because (a) on macOS, touching a promise through super_clipboard
      // resolves it destructively and silently empties the source app's
      // clipboard, breaking the user's own Cmd+V into Finder / Xcode /
      // Android Studio; (b) the native readFiles bridge on macOS
      // republishes resolved file URLs back to the pasteboard so the
      // user still gets a usable clipboard afterwards. Pre-prime ticks
      // (first observation after start) skip the actual resolve so we
      // don't trigger destructive promise handling for content that
      // pre-dates sclip's launch — same baseline rule as text/image.
      if (state.hasFiles) {
        if (!_primed) {
          _primed = true;
          return;
        }
        final paths = await _filesReader();
        if (paths.isEmpty) {
          // The native reader couldn't take the clipboard lock (or promise
          // resolution failed). Rewind the counter so the next tick retries
          // instead of permanently missing this file copy — the counter was
          // already consumed in step 1.
          _lastChange = previousChange;
          return;
        }
        // All-image file copies (Cmd+C in Finder of N PNGs, exporting an
        // imageSet from Photos, etc.) become a real imageSet entry so the
        // grid UI lights up and the per-image paste path stays available.
        // Mixed kinds, oversized files, or read failures fall back to a
        // plain files entry — the user still sees the file list and can
        // paste it.
        final entry = await _classifier.entryForFilePaths(paths);
        if (entry.contentHash == _lastSignature) return;
        _lastSignature = entry.contentHash;
        _controller.add(entry);
        return;
      }

      // Step 3 — read content.
      final ClipboardEntry? entry;
      if (_entryReaderOverride != null) {
        entry = await _entryReaderOverride();
      } else {
        final reader = await _readerFactory();
        if (reader == null) return;
        entry = await _classifier.read(reader);
      }
      if (entry == null) {
        _primed = true;
        return;
      }

      // Step 4 — content fingerprint dedup. Catches our own writeBack
      // (change counter bumps on every write, including writes we
      // initiated) and anything else that matches prior content.
      if (entry.contentHash == _lastSignature) return;
      _lastSignature = entry.contentHash;

      if (!_primed) {
        // First observation after start(): treat current clipboard as a
        // baseline so restarts don't re-surface whatever was copied earlier.
        _primed = true;
        return;
      }
      _controller.add(entry);
    } catch (e) {
      debugPrint('sclip: clipboard tick failed: $e');
    } finally {
      _ticking = false;
    }
  }
}
