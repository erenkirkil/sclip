import '../models/clipboard_entry.dart';
import 'search_text.dart';

/// Pure, allocation-only filter behind the search box.
///
/// Never touches [entries]: `HistoryProvider`'s mutation paths
/// (`removeAt`, `clear`) fire `onEvict`, which deletes the entry's
/// materialized temp files. A filter that removed in place would delete
/// real files as a side effect of typing. Both branches therefore return a
/// fresh fixed-length list — mutating the result is a loud error rather
/// than a silent write-through to the history.
///
/// An empty or whitespace-only [query] means "no filter" and yields the
/// full list in the original order.
List<ClipboardEntry> filterEntries(List<ClipboardEntry> entries, String query) {
  final needle = normalizeForSearch(query);
  if (needle.isEmpty) {
    return List<ClipboardEntry>.of(entries, growable: false);
  }
  return entries
      .where((entry) => entry.searchIndex.contains(needle))
      .toList(growable: false);
}
