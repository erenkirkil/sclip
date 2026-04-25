import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_entry.dart';

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

  /// Rewrites the OS clipboard with [entry]'s content. For
  /// [ClipboardEntryType.imageSet]: when [imageIndex] is null, every image
  /// in the set is written as its own clipboard item (multi-item payload);
  /// when provided, only that single image is written so a plain Cmd/Ctrl+V
  /// into an app that only accepts one item still gets the intended image.
  Future<void> writeBack(ClipboardEntry entry, {int? imageIndex}) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final item = DataWriterItem();
    switch (entry.type) {
      case ClipboardEntryType.text:
      case ClipboardEntryType.url:
      case ClipboardEntryType.color:
        final value = entry.text ?? '';
        if (value.isEmpty) return;
        item.add(Formats.plainText(value));
        break;
      case ClipboardEntryType.svg:
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
        item.add(_svgFormat(bytes));
        item.add(Formats.plainText(xml));
        break;
      case ClipboardEntryType.image:
        final bytes = entry.imageBytes;
        if (bytes == null || bytes.isEmpty) return;
        _addImageToItem(item, bytes, entry.imageFormat);
        break;
      case ClipboardEntryType.imageSet:
        final bytes = entry.imagesBytes;
        final formats = entry.imagesFormats;
        if (bytes == null || bytes.isEmpty) return;
        if (imageIndex == null) {
          // Paste-all: write each image to a temp file and publish via the
          // native CF_HDROP / NSURL writeObjects path so Finder / Explorer
          // light up alongside file-handler apps (Telegram, Slack, Mail).
          // Multi-item image payloads get silently collapsed to the first
          // item by most target apps under Cmd/Ctrl+V; file URIs are
          // treated as attachments and actually come through as a set.
          // Users who want a single inline image still have the
          // per-thumbnail paste path. The next tick will re-read the temp
          // files and rebuild the same imageSet (identical bytes ⇒
          // identical hash), so dedup against entry.contentHash suppresses
          // the self-ingestion.
          final paths = await _materializeImageSetToTempFiles(
            entry,
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
          return;
        }
        final i = imageIndex.clamp(0, bytes.length - 1);
        final fmt = (formats != null && i < formats.length)
            ? formats[i]
            : ClipboardImageFormat.png;
        _addImageToItem(item, bytes[i], fmt);
        await clipboard.write([item]);
        // Track the single-image signature we just wrote so the next tick
        // doesn't re-ingest it as a brand-new clipboard entry.
        _lastSignature = ClipboardEntry.image(
          bytes[i],
          format: fmt,
        ).contentHash;
        return;
      case ClipboardEntryType.files:
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
        return;
      case ClipboardEntryType.pdf:
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
      case ClipboardEntryType.richText:
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
        break;
    }
    await clipboard.write([item]);
    _lastSignature = entry.contentHash;
  }

  /// Writes [bytes] to `<tempDir>/sclip/<entryId>/clipboard.<ext>` and
  /// returns the file URI, or null if the temp dir is unavailable. Used by
  /// the SVG writeBack path so file-handler targets (Telegram, Slack) can
  /// pick up a file attachment instead of falling back to inline XML when
  /// they don't recognize the SVG UTI. Stale files from a prior writeBack
  /// on the same entry are pruned first to keep the temp dir bounded.
  Future<Uri?> _materializeBytesAsFile(
    ClipboardEntry entry,
    List<int> bytes,
    String extension,
  ) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/sclip/${entry.id}');
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {
          // ignore — we'll overwrite the file individually below
        }
      }
      dir.createSync(recursive: true);
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
  /// alongside the modern public.file-url payload. Files from a prior
  /// paste-all on this same entry are pruned first so the temp directory
  /// doesn't accumulate.
  Future<List<String>> _materializeImageSetToTempFiles(
    ClipboardEntry entry,
    List<Uint8List> bytes, {
    List<ClipboardImageFormat>? formats,
  }) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/sclip/${entry.id}');
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {
          // ignore — we'll overwrite files individually below
        }
      }
      dir.createSync(recursive: true);

      final paths = <String>[];
      for (var i = 0; i < bytes.length; i++) {
        final fmt = (formats != null && i < formats.length)
            ? formats[i]
            : ClipboardImageFormat.png;
        final ext = _extensionFor(fmt);
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

  static String _extensionFor(ClipboardImageFormat format) {
    switch (format) {
      case ClipboardImageFormat.png:
        return 'png';
      case ClipboardImageFormat.jpeg:
        return 'jpg';
      case ClipboardImageFormat.gif:
        return 'gif';
      case ClipboardImageFormat.webp:
        return 'webp';
    }
  }

  static void _addImageToItem(
    DataWriterItem item,
    Uint8List bytes,
    ClipboardImageFormat? format,
  ) {
    switch (format) {
      case ClipboardImageFormat.jpeg:
        item.add(Formats.jpeg(bytes));
      case ClipboardImageFormat.gif:
        item.add(Formats.gif(bytes));
      case ClipboardImageFormat.webp:
        item.add(Formats.webp(bytes));
      case ClipboardImageFormat.png:
      case null:
        item.add(Formats.png(bytes));
    }
  }

  Stream<ClipboardEntry> get entries => _controller.stream;
  bool get isRunning => _timer != null;

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
    // can't grow across restarts. Per-entry SVG/PDF/imageSet temp dirs
    // and the native readFiles destination dir all live under
    // <tempDir>/sclip/, so a single recursive delete here is enough.
    // Best-effort: any failure (permissions, locked file) is logged but
    // doesn't block the timer — at worst a few stale files survive
    // until the next start.
    unawaited(_pruneTempDir());
    _timer = Timer.periodic(_interval, (_) => _tick());
    _tick();
  }

  static Future<void> _pruneTempDir() async {
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

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      // Step 1 — cheap native probe. If the change counter hasn't moved,
      // the clipboard hasn't been touched since our last tick, so we skip
      // all work (no IPC to super_clipboard, no decoding, no allocations).
      final state = await _stateProbe();
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
        if (paths.isEmpty) return;
        // All-image file copies (Cmd+C in Finder of N PNGs, exporting an
        // imageSet from Photos, etc.) become a real imageSet entry so the
        // grid UI lights up and the per-image paste path stays available.
        // Mixed kinds, oversized files, or read failures fall back to a
        // plain files entry — the user still sees the file list and can
        // paste it.
        final entry = await _entryForFilePaths(paths);
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
        entry = await _read(reader);
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

  /// Filename extensions we recognise as raster images. Drives the
  /// "Finder copy of N PNGs becomes an imageSet" path in [_tick]. Sniffing
  /// magic bytes would catch mislabeled files but adds disk reads on
  /// every files-on-clipboard tick; extension is reliable enough for the
  /// shells that publish CF_HDROP / NSURL (Finder, Explorer, Photos).
  static const _imageFileExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp'};

  /// Per-file size guard for the file → image conversion. Mirrors the
  /// HistoryProvider default `maxImageBytes` (5 MiB) so we don't waste
  /// I/O reading bytes that the history layer would drop anyway.
  static const _maxImageInjectBytes = 5 * 1024 * 1024;

  /// Builds the richest entry for a list of file paths. When every path
  /// looks like a raster image and each file fits the per-image cap,
  /// reads bytes and returns an image / imageSet so the grid UI lights
  /// up. Falls back to a files entry for mixed or non-image content,
  /// oversized files, or read failures — the user still sees the file
  /// list and can paste it. Reads are sequential to avoid hammering the
  /// disk when a user has just dropped 30+ files on the clipboard.
  Future<ClipboardEntry> _entryForFilePaths(List<String> paths) async {
    ClipboardEntry filesFallback() =>
        ClipboardEntry.files([for (final p in paths) Uri.file(p)]);
    final formats = <ClipboardImageFormat>[];
    for (final p in paths) {
      final ext = _extensionOfPath(p);
      if (!_imageFileExtensions.contains(ext)) {
        return filesFallback();
      }
      formats.add(_imageFormatForExtension(ext));
    }
    final bytesList = <Uint8List>[];
    for (final p in paths) {
      try {
        final f = File(p);
        final stat = await f.stat();
        if (stat.size <= 0 || stat.size > _maxImageInjectBytes) {
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

  static ClipboardImageFormat _imageFormatForExtension(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return ClipboardImageFormat.jpeg;
      case 'gif':
        return ClipboardImageFormat.gif;
      case 'webp':
        return ClipboardImageFormat.webp;
      case 'png':
      default:
        return ClipboardImageFormat.png;
    }
  }

  static final _svgFormat = SimpleFileFormat(
    uniformTypeIdentifiers: ['public.svg-image'],
    mimeTypes: ['image/svg+xml'],
  );

  /// Hard cap for SVG payloads. Real vector assets from Figma/Illustrator
  /// routinely run 3-6 MB; 20 MB is comfortably above that while still
  /// cutting off obviously-malicious oversize payloads cheaply. The primary
  /// defense against Billion-Laughs-style expansion is the DOCTYPE/ENTITY
  /// reject below — size alone is not a defense there (a <1 KB file can
  /// expand to gigabytes).
  static const _maxSvgBytes = 20 * 1024 * 1024;

  /// Per-entry cap for PDF payloads. 25 MB covers the vast majority of
  /// pasted documents (academic papers, invoices, reports) without letting
  /// a single oversized payload balloon RAM — at the 30-item history cap a
  /// PDF flood would still stay under ~750 MB resident worst-case.
  static const _maxPdfBytes = 25 * 1024 * 1024;

  /// Byte-level pre-parse check: reject SVG payloads that contain XXE /
  /// XInclude constructs before we hand them to flutter_svg. Scans only
  /// the first 4 KB because DOCTYPE / ENTITY / ATTLIST declarations must
  /// precede the root element by XML rules, so a malicious payload can't
  /// hide them deeper in the file. `allowMalformed: true` so non-UTF-8
  /// garbage decodes to replacement chars instead of throwing — we still
  /// reject it on content grounds downstream.
  /// Heuristic for "this plain-text payload is actually SVG markup". Trim
  /// + lowercase the head, allow an optional XML prolog, then require a
  /// `<svg` open tag and a `</svg>` close. Restrictive enough that we
  /// don't accidentally treat HTML snippets containing inline `<svg>`
  /// fragments as standalone SVG documents.
  static bool _looksLikeSvgXml(String text) {
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

  @visibleForTesting
  static bool isSafeSvgPayload(Uint8List bytes) {
    if (bytes.length > _maxSvgBytes) return false;
    final headLen = bytes.length < 4096 ? bytes.length : 4096;
    final head = utf8.decode(bytes.sublist(0, headLen), allowMalformed: true);
    if (head.contains('<!DOCTYPE') ||
        head.contains('<!ENTITY') ||
        head.contains('<!ATTLIST')) {
      return false;
    }
    if (head.contains('xmlns:xi=') || head.contains('XInclude')) {
      return false;
    }
    return true;
  }

  Future<ClipboardEntry?> _read(ClipboardReader reader) async {
    // Classify each pasteboard item independently. The all-images fast path
    // (multi-screenshot, design exports) becomes a single imageSet so the
    // grid UI lights up. Anything else multi-item collapses to the richest
    // single classified entry — heterogeneous super_clipboard payloads
    // (e.g. Figma's "image + text" pair) are vanishingly rare in practice
    // and storing a hybrid record the UI can't render usefully isn't worth
    // the architectural weight. The user can always re-copy the other half.
    final classified = <ClipboardEntry>[];
    for (final item in reader.items) {
      final c = await _classifyItem(item);
      if (c != null) classified.add(c);
    }
    if (classified.isEmpty) return null;
    if (classified.length == 1) return classified.first;

    if (classified.every((e) => e.type == ClipboardEntryType.image)) {
      return ClipboardEntry.imageSet(
        [for (final e in classified) e.imageBytes!],
        formats: [
          for (final e in classified) e.imageFormat ?? ClipboardImageFormat.png,
        ],
      );
    }

    // Mixed payload: pick the richest single entry. Priority mirrors the
    // per-item probe order — image > svg > pdf > richText > url > color >
    // text — so the user gets the visually heaviest representation. Stable
    // sort keeps original copy order as the tiebreaker.
    classified.sort(
      (a, b) => (_richness[b.type] ?? 0).compareTo(_richness[a.type] ?? 0),
    );
    return classified.first;
  }

  static const _richness = {
    ClipboardEntryType.image: 6,
    ClipboardEntryType.svg: 5,
    ClipboardEntryType.pdf: 4,
    ClipboardEntryType.richText: 3,
    ClipboardEntryType.url: 2,
    ClipboardEntryType.color: 1,
    ClipboardEntryType.text: 0,
  };

  /// Probes a single pasteboard item in priority order (image → svg → pdf →
  /// text/url/color/richText → html-only) and returns the richest
  /// [ClipboardEntry] representation we can build. Returns null if nothing
  /// recognized — file URIs are intentionally skipped here (NSFilePromise
  /// resolution would empty the source app's clipboard, see the long
  /// comment in [_tick]).
  Future<ClipboardEntry?> _classifyItem(ClipboardDataReader item) async {
    for (final tag in ClipboardImageFormat.values) {
      final format = _formatFor(tag);
      if (!item.canProvide(format)) continue;
      final bytes = await _readBinary(item, format);
      if (bytes != null && bytes.isNotEmpty) {
        return ClipboardEntry.image(bytes, format: tag);
      }
    }

    if (item.canProvide(_svgFormat)) {
      final bytes = await _readBinary(item, _svgFormat);
      if (bytes != null && bytes.isNotEmpty && isSafeSvgPayload(bytes)) {
        try {
          return ClipboardEntry.svg(utf8.decode(bytes));
        } catch (_) {
          // Non-UTF-8 payload — skip SVG
        }
      }
    }

    if (item.canProvide(Formats.pdf)) {
      final bytes = await _readBinary(item, Formats.pdf);
      if (bytes != null && bytes.isNotEmpty) {
        if (bytes.length > _maxPdfBytes) {
          debugPrint(
            'sclip: dropping oversized PDF payload '
            '(${bytes.length} bytes > $_maxPdfBytes)',
          );
        } else {
          return ClipboardEntry.pdf(bytes);
        }
      }
    }

    if (item.canProvide(Formats.plainText)) {
      final text = await _readText(item, Formats.plainText);
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
        // SVG XML pasted as plain text (browser "View Source" copy, code
        // editors) doesn't carry the public.svg-image UTI, so the binary
        // SVG branch above misses it. Recognise the markup directly so the
        // tile still renders the SVG and writeBack publishes it as a file
        // for paste-into-Telegram fidelity. Same XXE guard as the binary
        // path — the sanitizer is the only thing standing between us and
        // a malicious payload here.
        if (_looksLikeSvgXml(text)) {
          final bytes = Uint8List.fromList(utf8.encode(text));
          if (isSafeSvgPayload(bytes)) {
            return ClipboardEntry.svg(text);
          }
        }
        if (item.canProvide(Formats.htmlText)) {
          final html = await _readText(item, Formats.htmlText);
          if (html != null && html.isNotEmpty && html != text) {
            return ClipboardEntry.richText(plainText: text, html: html);
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
      if (html != null && html.isNotEmpty) {
        final stripped = html
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (stripped.isNotEmpty) {
          return ClipboardEntry.richText(plainText: stripped, html: html);
        }
      }
    }

    return null;
  }

  static FileFormat _formatFor(ClipboardImageFormat tag) {
    switch (tag) {
      case ClipboardImageFormat.png:
        return Formats.png;
      case ClipboardImageFormat.jpeg:
        return Formats.jpeg;
      case ClipboardImageFormat.gif:
        return Formats.gif;
      case ClipboardImageFormat.webp:
        return Formats.webp;
    }
  }

  Future<String?> _readText(DataReader reader, ValueFormat<String> format) {
    final completer = Completer<String?>();
    reader.getValue<String>(format, (value) {
      if (!completer.isCompleted) completer.complete(value);
    });
    return completer.future;
  }

  Future<Uint8List?> _readBinary(DataReader reader, FileFormat format) {
    final completer = Completer<Uint8List?>();
    reader.getFile(
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
    return completer.future;
  }
}
