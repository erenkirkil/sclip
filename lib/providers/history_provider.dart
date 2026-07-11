import 'package:flutter/foundation.dart';

import '../models/clipboard_entry.dart';

class HistoryProvider extends ChangeNotifier {
  HistoryProvider({
    int maxItems = 30,
    this.maxImageBytes = 5 * 1024 * 1024,
    this.maxTotalImageBytes = 150 * 1024 * 1024,
  }) : _maxItems = maxItems;

  /// Default kept conservative — clipboard managers balloon RAM quickly
  /// when users copy screenshots. 30 is comfortable for daily use.
  int _maxItems;
  int get maxItems => _maxItems;

  /// Mutable at runtime so the settings page can lower the cap on the fly.
  /// Dropping below current length truncates the tail immediately; raising
  /// the cap is a no-op until new entries arrive.
  set maxItems(int value) {
    if (value <= 0 || value == _maxItems) return;
    _maxItems = value;
    if (_entries.length > _maxItems) {
      _truncateToMax();
      notifyListeners();
    }
  }

  /// Invoked for every entry that permanently leaves the history (FIFO
  /// eviction, delete, clear, dedup replacement). Lets the clipboard
  /// service delete the entry's materialized temp files so pasted content
  /// doesn't linger on disk until the next launch. touch() reinsertion is
  /// not an eviction and does not fire this.
  void Function(ClipboardEntry entry)? onEvict;

  /// Per-entry image byte cap. Anything larger is dropped on ingest so a
  /// single oversized paste can't push the process into hundreds of MB.
  final int maxImageBytes;

  /// Sum cap across all *heavy* entries — raw images, imageSets, PDFs and
  /// large text/HTML/SVG strings. Without this, 30 copies of 4K
  /// screenshots (~8MB each) would sit at ~240MB resident even while each
  /// individual entry is under [maxImageBytes] — and PDFs (25MB per-entry
  /// cap) used to escape the budget entirely (30 × 25MB = 750MB worst
  /// case). When adding a heavy entry would push the total over this
  /// limit, the oldest heavy entries are evicted FIFO until the new one
  /// fits. Zero-weight entries (urls, colors, file URI lists) are never
  /// counted or evicted by the budget.
  final int maxTotalImageBytes;

  final List<ClipboardEntry> _entries = [];

  List<ClipboardEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Ingests a new entry. Hash-based dedup: if an entry with the same
  /// content hash already exists, it's removed so the new one rises to the
  /// top with a fresh timestamp. Oversized images are silently dropped;
  /// image entries that would push total image memory over
  /// [maxTotalImageBytes] evict older image entries to make room.
  void add(ClipboardEntry entry) {
    final entryImageBytes = _imageBytesOf(entry);

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
      if (bytes == null || bytes.isEmpty || entryImageBytes > maxImageBytes) {
        debugPrint(
          'sclip: dropping oversized image-set entry '
          '($entryImageBytes bytes > $maxImageBytes)',
        );
        return;
      }
    }

    if (_entries.isNotEmpty &&
        _entries.first.contentHash == entry.contentHash) {
      return;
    }

    // Reject entries whose own bytes exceed the total cap up front — no
    // amount of eviction would make room. Otherwise eviction is guaranteed
    // to succeed (worst case: every other image entry is dropped), so it's
    // safe to commit to mutating the list.
    if (entryImageBytes > maxTotalImageBytes) {
      debugPrint(
        'sclip: dropping image entry that exceeds total cap '
        '($entryImageBytes bytes > $maxTotalImageBytes)',
      );
      return;
    }
    if (entryImageBytes > 0) {
      final existingIdx = _entries.indexWhere(
        (e) => e.contentHash == entry.contentHash,
      );
      final existingBytes = existingIdx >= 0
          ? _imageBytesOf(_entries[existingIdx])
          : 0;
      var projected = _totalImageBytes() - existingBytes + entryImageBytes;
      while (projected > maxTotalImageBytes) {
        final victimIdx = _entries.lastIndexWhere(
          (e) => _carriesImage(e) && e.contentHash != entry.contentHash,
        );
        if (victimIdx < 0) break;
        final victim = _entries.removeAt(victimIdx);
        projected -= _imageBytesOf(victim);
        onEvict?.call(victim);
      }
    }

    final existingIndex = _entries.indexWhere(
      (e) => e.contentHash == entry.contentHash,
    );
    if (existingIndex >= 0) {
      // Dedup replacement: the incoming entry has a fresh id, so the old
      // entry (and any temp files keyed by its id) is gone for good.
      // NOTE: the removal must happen outside the `?.` call — Dart
      // short-circuits argument evaluation when the target is null.
      final replaced = _entries.removeAt(existingIndex);
      onEvict?.call(replaced);
    }
    _entries.insert(0, entry);
    _truncateToMax();
    notifyListeners();
  }

  /// Drops everything past [_maxItems], firing [onEvict] per victim.
  void _truncateToMax() {
    while (_entries.length > _maxItems) {
      final victim = _entries.removeLast();
      onEvict?.call(victim);
    }
  }

  static bool _carriesImage(ClipboardEntry e) => _imageBytesOf(e) > 0;

  /// Budget weight of an entry. Exhaustive on purpose — a `default:`
  /// here is exactly how PDFs silently escaped the total budget when the
  /// type was added; the next byte-carrying type must fail to compile
  /// until someone decides its weight. String lengths are UTF-16 code
  /// units, ≈ bytes for the ASCII-dominated payloads we care about.
  static int _imageBytesOf(ClipboardEntry e) => switch (e.type) {
    ClipboardEntryType.image => e.imageBytes?.lengthInBytes ?? 0,
    ClipboardEntryType.imageSet =>
      e.imagesBytes?.fold<int>(0, (s, b) => s + b.lengthInBytes) ?? 0,
    ClipboardEntryType.pdf => e.pdfBytes?.lengthInBytes ?? 0,
    ClipboardEntryType.svg => _stringWeight(e.text?.length),
    ClipboardEntryType.richText => _stringWeight(
      (e.text?.length ?? 0) + (e.richTextHtml?.length ?? 0),
    ),
    ClipboardEntryType.text => _stringWeight(e.text?.length),
    // URI lists and short parsed strings — negligible by construction.
    ClipboardEntryType.url ||
    ClipboardEntryType.color ||
    ClipboardEntryType.files => 0,
  };

  /// Strings below this size weigh zero: they neither strain the budget
  /// (30 × 64KB ≈ 2MB worst case unaccounted) nor deserve to be evicted
  /// as "heavy" victims to make room for a screenshot.
  static const _stringWeightFloor = 64 * 1024;
  static int _stringWeight(int? length) {
    final n = length ?? 0;
    return n < _stringWeightFloor ? 0 : n;
  }

  int _totalImageBytes() =>
      _entries.fold<int>(0, (s, e) => s + _imageBytesOf(e));

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
    final removed = _entries.removeAt(index);
    onEvict?.call(removed);
    notifyListeners();
  }

  void removeById(String id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i >= 0) removeAt(i);
  }

  void clear() {
    if (_entries.isEmpty) return;
    final victims = List.of(_entries);
    _entries.clear();
    for (final e in victims) {
      onEvict?.call(e);
    }
    notifyListeners();
  }
}
