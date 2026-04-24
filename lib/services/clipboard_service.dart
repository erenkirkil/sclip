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

/// Snapshot returned by the native `currentState` channel: a monotonic
/// change counter (macOS NSPasteboard.changeCount / Windows
/// GetClipboardSequenceNumber), a sensitive-content flag, and a file-promise
/// flag used to skip super_clipboard reads that would resolve NSFilePromise
/// entries (emptying the source app's clipboard in the process). A missing
/// native handler is expressed as [ClipboardState.unavailable].
class ClipboardState {
  const ClipboardState({
    required this.change,
    required this.sensitive,
    this.hasFilePromise = false,
  });

  static const unavailable = ClipboardState(change: -1, sensitive: false);

  final int change;
  final bool sensitive;
  final bool hasFilePromise;
}

typedef ClipboardStateProbe = Future<ClipboardState> Function();

class ClipboardService {
  ClipboardService({
    Duration interval = const Duration(milliseconds: 500),
    ClipboardReaderFactory? readerFactory,
    ClipboardEntryReader? entryReader,
    ClipboardStateProbe? stateProbe,
  })  : _interval = interval,
        _readerFactory = readerFactory ?? _defaultReader,
        _entryReaderOverride = entryReader,
        _stateProbe = stateProbe ?? _defaultStateProbe;

  static const _metaChannel = MethodChannel('sclip/clipboard');

  final Duration _interval;
  final ClipboardReaderFactory _readerFactory;
  final ClipboardEntryReader? _entryReaderOverride;
  final ClipboardStateProbe _stateProbe;
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
          // Paste-all: write each image to a temp file and publish as file
          // URIs. Multi-item image payloads get silently collapsed to the
          // first item by most target apps (Slack, Discord, Notes all
          // behave this way under Cmd/Ctrl+V), whereas file URIs are
          // treated as attachments/files and actually come through as a
          // set. Users who want a single inline image still have the
          // per-thumbnail paste path.
          final items = await _materializeImageSetAsFiles(entry, bytes,
              formats: formats);
          if (items.isEmpty) return;
          await clipboard.write(items);
          // Written as file URIs now, not raster bytes — the next clipboard
          // tick will see a different type entirely, so the imageSet
          // contentHash wouldn't match. Record a file-style signature so
          // self-ingestion is still suppressed.
          _lastSignature = 'paste-all:${entry.id}:${entry.contentHash}';
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
        _lastSignature = ClipboardEntry.image(bytes[i], format: fmt)
            .contentHash;
        return;
      case ClipboardEntryType.files:
        final uris = entry.uris;
        if (uris == null || uris.isEmpty) return;
        final items = uris
            .map((uri) => DataWriterItem()..add(Formats.fileUri(uri)))
            .toList();
        await clipboard.write(items);
        _lastSignature = entry.contentHash;
        return;
    }
    await clipboard.write([item]);
    _lastSignature = entry.contentHash;
  }

  /// Writes each image in [bytes] to a temp file under
  /// `<tempDir>/sclip/<entryId>/` and returns one [DataWriterItem] per
  /// file — each carrying the file URI so target apps see a multi-file
  /// paste instead of a multi-image pasteboard (which most apps collapse
  /// to the first item). Files from the previous paste-all for the same
  /// entry are pruned first so the temp directory doesn't accumulate.
  Future<List<DataWriterItem>> _materializeImageSetAsFiles(
    ClipboardEntry entry,
    List<Uint8List> bytes, {
    List<ClipboardImageFormat>? formats,
  }) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/sclip/${entry.id}');
      if (dir.existsSync()) {
        // Drop stale files from a prior paste-all on this same entry to
        // keep the temp dir bounded — we always overwrite on every call.
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {
          // ignore — we'll overwrite files individually below
        }
      }
      dir.createSync(recursive: true);

      final items = <DataWriterItem>[];
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
        final item = DataWriterItem()..add(Formats.fileUri(file.uri));
        items.add(item);
      }
      return items;
    } catch (e) {
      debugPrint('sclip: paste-all temp materialize failed: $e');
      return const [];
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
        hasFilePromise: (v['hasFilePromise'] as bool?) ?? false,
      );
    } on MissingPluginException {
      return ClipboardState.unavailable;
    } catch (e) {
      debugPrint('sclip: clipboard state probe failed: $e');
      return ClipboardState.unavailable;
    }
  }

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => _tick());
    _tick();
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
      // next non-sensitive copy still counts as "new".
      if (state.sensitive) return;

      // Step 2b — file-promise short-circuit. Finder / Android Studio /
      // Xcode publish selections as NSFilePromise; calling
      // super_clipboard.read() on them triggers the promise resolution,
      // which writes placeholder files into our temp dir AND empties the
      // source app's clipboard so the user's own Cmd+V fails silently
      // afterward. We check "has any promise type" rather than "is
      // file-only" — Finder routinely publishes the filename as plain
      // text alongside the promise, so an allSatisfy check would miss
      // the common case. We don't surface file entries anyway (see the
      // comment in _read), so false negatives here cost nothing beyond
      // the rare rich-copy payload that bundles a promise with raster
      // bytes — acceptable trade for reliably not breaking Finder.
      if (state.hasFilePromise) {
        _primed = true;
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

  /// Byte-level pre-parse check: reject SVG payloads that contain XXE /
  /// XInclude constructs before we hand them to flutter_svg. Scans only
  /// the first 4 KB because DOCTYPE / ENTITY / ATTLIST declarations must
  /// precede the root element by XML rules, so a malicious payload can't
  /// hide them deeper in the file. `allowMalformed: true` so non-UTF-8
  /// garbage decodes to replacement chars instead of throwing — we still
  /// reject it on content grounds downstream.
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
    // Image formats, tried in order. PNG first because macOS screenshots
    // and most screenshot tools emit it; JPEG for photos; GIF/WebP for
    // browser "Copy Image" flows.
    const imageAttempts = [
      (ClipboardImageFormat.png, 'png'),
      (ClipboardImageFormat.jpeg, 'jpeg'),
      (ClipboardImageFormat.gif, 'gif'),
      (ClipboardImageFormat.webp, 'webp'),
    ];

    // Multi-image copy (e.g. selecting several images in a design tool)
    // lands as a ClipboardReader whose `items` list holds one raster per
    // slot. Fan them in here rather than at the UI layer so the history
    // stores a single slot — otherwise one copy-of-six would evict
    // everything else under the 30-item cap.
    final images = <(Uint8List, ClipboardImageFormat)>[];
    for (final item in reader.items) {
      for (final (tag, _) in imageAttempts) {
        final format = _formatFor(tag);
        if (!item.canProvide(format)) continue;
        final bytes = await _readBinary(item, format);
        if (bytes != null && bytes.isNotEmpty) {
          images.add((bytes, tag));
          break;
        }
      }
    }
    if (images.length >= 2) {
      return ClipboardEntry.imageSet(
        [for (final (b, _) in images) b],
        formats: [for (final (_, f) in images) f],
      );
    }
    if (images.length == 1) {
      final (bytes, tag) = images.first;
      return ClipboardEntry.image(bytes, format: tag);
    }

    if (reader.canProvide(_svgFormat)) {
      final bytes = await _readBinary(reader, _svgFormat);
      if (bytes != null && bytes.isNotEmpty && isSafeSvgPayload(bytes)) {
        try {
          return ClipboardEntry.svg(utf8.decode(bytes));
        } catch (_) {
          // Non-UTF-8 payload — skip SVG
        }
      }
    }

    if (reader.canProvide(Formats.plainText)) {
      final text = await _readText(reader, Formats.plainText);
      if (text != null && text.isNotEmpty) {
        if (ClipboardEntry.looksLikeUrl(text)) {
          return ClipboardEntry.url(Uri.parse(text.trim()));
        }
        if (ClipboardEntry.looksLikeColor(text)) {
          return ClipboardEntry.color(text);
        }
        return ClipboardEntry.text(text);
      }
    }

    // File URIs are intentionally skipped. On macOS apps like Finder and
    // Android Studio publish files as NSFilePromise, and reading via
    // super_clipboard's getValue resolves the promise, leaving the original
    // clipboard empty — a later Cmd+V in the source app then silently fails.
    // Since we can't reliably re-emit the promise on paste, we leave file
    // copies to the OS clipboard entirely.

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

  Future<String?> _readText(
    DataReader reader,
    ValueFormat<String> format,
  ) {
    final completer = Completer<String?>();
    reader.getValue<String>(format, (value) {
      if (!completer.isCompleted) completer.complete(value);
    });
    return completer.future;
  }

  Future<Uint8List?> _readBinary(
    DataReader reader,
    FileFormat format,
  ) {
    final completer = Completer<Uint8List?>();
    reader.getFile(format, (file) async {
      try {
        final bytes = await file.readAll();
        if (!completer.isCompleted) completer.complete(bytes);
      } catch (e) {
        debugPrint('sclip: binary read failed for ${format.runtimeType}: $e');
        if (!completer.isCompleted) completer.complete(null);
      }
    }, onError: (e) {
      debugPrint('sclip: binary read errored: $e');
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }
}
