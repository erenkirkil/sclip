import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_entry.dart';

typedef ClipboardReaderFactory = Future<ClipboardReader?> Function();
typedef ClipboardEntryReader = Future<ClipboardEntry?> Function();

class ClipboardService {
  ClipboardService({
    Duration interval = const Duration(milliseconds: 500),
    ClipboardReaderFactory? readerFactory,
    ClipboardEntryReader? entryReader,
  })  : _interval = interval,
        _readerFactory = readerFactory ?? _defaultReader,
        _entryReaderOverride = entryReader;

  final Duration _interval;
  final ClipboardReaderFactory _readerFactory;
  final ClipboardEntryReader? _entryReaderOverride;
  final StreamController<ClipboardEntry> _controller =
      StreamController<ClipboardEntry>.broadcast();

  Timer? _timer;
  String? _lastSignature;
  bool _ticking = false;

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
        item.add(Formats.png(bytes));
        break;
      case ClipboardEntryType.files:
        return;
    }
    await clipboard.write([item]);
    _lastSignature = _signature(entry);
  }

  Stream<ClipboardEntry> get entries => _controller.stream;
  bool get isRunning => _timer != null;

  static Future<ClipboardReader?> _defaultReader() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    return clipboard.read();
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
      final ClipboardEntry? entry;
      if (_entryReaderOverride != null) {
        entry = await _entryReaderOverride();
      } else {
        final reader = await _readerFactory();
        if (reader == null) return;
        entry = await _read(reader);
      }
      if (entry == null) return;
      final sig = _signature(entry);
      if (sig == _lastSignature) return;
      _lastSignature = sig;
      _controller.add(entry);
    } catch (_) {
      // Swallow transient read errors; next tick will retry.
    } finally {
      _ticking = false;
    }
  }

  Future<ClipboardEntry?> _read(ClipboardReader reader) async {
    if (reader.canProvide(Formats.png)) {
      final bytes = await _readBinary(reader, Formats.png);
      if (bytes != null && bytes.isNotEmpty) {
        return ClipboardEntry.image(bytes);
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
        if (!completer.isCompleted) completer.complete(null);
      }
    }, onError: (_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  String _signature(ClipboardEntry entry) {
    switch (entry.type) {
      case ClipboardEntryType.text:
      case ClipboardEntryType.url:
      case ClipboardEntryType.color:
        return 'txt:${entry.text}';
      case ClipboardEntryType.image:
        final bytes = entry.imageBytes;
        if (bytes == null || bytes.isEmpty) return 'img:0';
        final len = bytes.length;
        var sum = 0;
        for (var i = 0; i < bytes.length; i += (bytes.length ~/ 64).clamp(1, 1024)) {
          sum = (sum + bytes[i]) & 0xFFFFFF;
        }
        return 'img:$len:$sum';
      case ClipboardEntryType.files:
        return 'files:${entry.uris?.map((u) => u.toString()).join("|")}';
    }
  }
}
