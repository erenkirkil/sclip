import 'package:flutter/foundation.dart';

import '../models/clipboard_entry.dart';

class HistoryProvider extends ChangeNotifier {
  HistoryProvider({
    this.maxItems = 30,
    this.maxImageBytes = 5 * 1024 * 1024,
  });

  /// Default kept conservative — clipboard managers balloon RAM quickly
  /// when users copy screenshots. 30 is comfortable for daily use.
  final int maxItems;

  /// Per-entry image byte cap. Anything larger is dropped on ingest so a
  /// single oversized paste can't push the process into hundreds of MB.
  final int maxImageBytes;

  final List<ClipboardEntry> _entries = [];

  List<ClipboardEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Ingests a new entry. Hash-based dedup: if an entry with the same
  /// content hash already exists, it's removed so the new one rises to the
  /// top with a fresh timestamp. Oversized images are silently dropped.
  void add(ClipboardEntry entry) {
    if (entry.type == ClipboardEntryType.image) {
      final bytes = entry.imageBytes;
      if (bytes == null || bytes.lengthInBytes > maxImageBytes) {
        debugPrint(
          'sclip: dropping oversized image entry '
          '(${bytes?.lengthInBytes ?? 0} bytes > $maxImageBytes)',
        );
        return;
      }
    }
    if (entry.type == ClipboardEntryType.imageSet) {
      final bytes = entry.imagesBytes;
      // Total-bytes cap rather than per-image — the concern here is one
      // paste spiking memory, and a 10-image set is just as risky as a
      // single 5MB image.
      final total = bytes?.fold<int>(0, (s, b) => s + b.lengthInBytes) ?? 0;
      if (bytes == null || bytes.isEmpty || total > maxImageBytes) {
        debugPrint(
          'sclip: dropping oversized image-set entry '
          '($total bytes > $maxImageBytes)',
        );
        return;
      }
    }

    if (_entries.isNotEmpty &&
        _entries.first.contentHash == entry.contentHash) {
      return;
    }
    final existingIndex =
        _entries.indexWhere((e) => e.contentHash == entry.contentHash);
    if (existingIndex >= 0) {
      _entries.removeAt(existingIndex);
    }
    _entries.insert(0, entry);
    if (_entries.length > maxItems) {
      _entries.removeRange(maxItems, _entries.length);
    }
    notifyListeners();
  }

  /// Moves the entry with [id] to the top and refreshes its createdAt
  /// without changing any other field. Used when the user taps an existing
  /// entry to re-copy it — the "just now" label should reflect the latest
  /// action while keeping the entry identity stable for the widget key.
  void touch(String id) {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final entry = _entries[idx];
    _entries.removeAt(idx);
    _entries.insert(0, entry.touched());
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _entries.length) return;
    _entries.removeAt(index);
    notifyListeners();
  }

  void removeById(String id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i >= 0) removeAt(i);
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
