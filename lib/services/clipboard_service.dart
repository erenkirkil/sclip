import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_entry.dart';

typedef ClipboardReaderFactory = Future<ClipboardReader?> Function();
typedef ClipboardEntryReader = Future<ClipboardEntry?> Function();

/// Snapshot returned by the native `currentState` channel: a monotonic
/// change counter (macOS NSPasteboard.changeCount / Windows
/// GetClipboardSequenceNumber) and a sensitive-content flag. A missing
/// native handler is expressed as [ClipboardState.unavailable].
class ClipboardState {
  const ClipboardState({required this.change, required this.sensitive});

  static const unavailable = ClipboardState(change: -1, sensitive: false);

  final int change;
  final bool sensitive;
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

  Future<void> writeBack(ClipboardEntry entry) async {
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
      case ClipboardEntryType.image:
        final bytes = entry.imageBytes;
        if (bytes == null || bytes.isEmpty) return;
        switch (entry.imageFormat) {
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
        break;
      case ClipboardEntryType.files:
        return;
    }
    await clipboard.write([item]);
    _lastSignature = entry.contentHash;
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

  Future<ClipboardEntry?> _read(ClipboardReader reader) async {
    // Image formats, tried in order. PNG first because macOS screenshots
    // and most screenshot tools emit it; JPEG for photos; GIF/WebP for
    // browser "Copy Image" flows.
    final imageAttempts = [
      (Formats.png, ClipboardImageFormat.png),
      (Formats.jpeg, ClipboardImageFormat.jpeg),
      (Formats.gif, ClipboardImageFormat.gif),
      (Formats.webp, ClipboardImageFormat.webp),
    ];
    for (final (format, tag) in imageAttempts) {
      if (!reader.canProvide(format)) continue;
      final bytes = await _readBinary(reader, format);
      if (bytes != null && bytes.isNotEmpty) {
        return ClipboardEntry.image(bytes, format: tag);
      }
    }

    if (reader.canProvide(_svgFormat)) {
      final bytes = await _readBinary(reader, _svgFormat);
      if (bytes != null && bytes.isNotEmpty) {
        try {
          return ClipboardEntry.text(utf8.decode(bytes));
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

    if (reader.canProvide(Formats.fileUri)) {
      final uri = await _readValue(reader, Formats.fileUri);
      if (uri != null) return ClipboardEntry.files([uri]);
    }

    return null;
  }

  Future<String?> _readText(
    ClipboardReader reader,
    ValueFormat<String> format,
  ) {
    final completer = Completer<String?>();
    reader.getValue<String>(format, (value) {
      if (!completer.isCompleted) completer.complete(value);
    });
    return completer.future;
  }

  Future<T?> _readValue<T extends Object>(
    ClipboardReader reader,
    ValueFormat<T> format,
  ) {
    final completer = Completer<T?>();
    reader.getValue<T>(format, (value) {
      if (!completer.isCompleted) completer.complete(value);
    });
    return completer.future;
  }

  Future<Uint8List?> _readBinary(
    ClipboardReader reader,
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
