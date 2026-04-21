import 'package:flutter/foundation.dart';

import '../models/clipboard_entry.dart';

class HistoryProvider extends ChangeNotifier {
  HistoryProvider({this.maxItems = 200});

  final int maxItems;
  final List<ClipboardEntry> _entries = [];

  List<ClipboardEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  void add(ClipboardEntry entry) {
    if (_entries.isNotEmpty && _isSameContent(_entries.first, entry)) {
      return;
    }
    final existingIndex = _entries.indexWhere((e) => _isSameContent(e, entry));
    if (existingIndex >= 0) {
      _entries.removeAt(existingIndex);
    }
    _entries.insert(0, entry);
    if (_entries.length > maxItems) {
      _entries.removeRange(maxItems, _entries.length);
    }
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

  bool _isSameContent(ClipboardEntry a, ClipboardEntry b) {
    if (a.type != b.type) return false;
    switch (a.type) {
      case ClipboardEntryType.text:
      case ClipboardEntryType.url:
      case ClipboardEntryType.color:
        return a.text == b.text;
      case ClipboardEntryType.image:
        final ab = a.imageBytes;
        final bb = b.imageBytes;
        if (ab == null || bb == null) return false;
        if (ab.length != bb.length) return false;
        return identical(ab, bb);
      case ClipboardEntryType.files:
        final au = a.uris ?? const [];
        final bu = b.uris ?? const [];
        if (au.length != bu.length) return false;
        for (var i = 0; i < au.length; i++) {
          if (au[i] != bu[i]) return false;
        }
        return true;
    }
  }
}
