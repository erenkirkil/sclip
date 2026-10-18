/// Locale-independent text normalization shared by the search index
/// ([ClipboardEntry.searchIndex]) and the query box. Deliberately
/// dependency-free: the model imports it, so it must not pull Flutter in.
///
/// Dart's `toLowerCase()` is Unicode-default, not locale-aware, and that
/// breaks Turkish systematically: `'IŞIK'.toLowerCase()` yields `'işik'`
/// (dotted i) instead of `'ışık'`, and `'İ'.toLowerCase()` collapses to a
/// bare `'i'`. Lowercasing alone would therefore make a query match or
/// miss depending on which of the four I's the user happened to type. We
/// fold the whole dotted/dotless I family to ASCII `i` *before*
/// lowercasing, then strip the remaining Turkish diacritics so "gozluk"
/// finds "Gözlük" and "cagri" finds "ÇAĞRI".
library;

/// I-family folds applied before [String.toLowerCase]. `ı` (U+0131) is the
/// reason this pass exists: lowercasing leaves it untouched, so a
/// post-lowercase table alone would still split `ışık` from `IŞIK`.
const Map<int, int> _preLowerFolds = <int, int>{
  0x0049: 0x69, // I → i
  0x0130: 0x69, // İ → i
  0x0131: 0x69, // ı → i
};

/// Diacritic folds applied after lowercasing, so only lowercase forms need
/// entries here (`Ş` has already become `ş`). The circumflex vowels are
/// included because Turkish spelling drops them freely (kâğıt/kagit).
const Map<int, int> _diacriticFolds = <int, int>{
  0x015F: 0x73, // ş → s
  0x011F: 0x67, // ğ → g
  0x00FC: 0x75, // ü → u
  0x00F6: 0x6F, // ö → o
  0x00E7: 0x63, // ç → c
  0x00E2: 0x61, // â → a
  0x00EE: 0x69, // î → i
  0x00FB: 0x75, // û → u
};

/// Space, tab, LF, VT, FF, CR and NBSP. Kept as an explicit range test
/// instead of a RegExp: this runs over every indexed entry on ingest.
bool _isWhitespace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0x00A0;

/// Folds [input] into the canonical search form: I-family → `i`,
/// lowercase, diacritics stripped, whitespace runs collapsed to a single
/// space, ends trimmed. A blank or whitespace-only input normalizes to the
/// empty string, which is what [filterEntries] treats as "no filter".
///
/// Iterates code units, not runes: every key in both fold tables is BMP,
/// so surrogate pairs (emoji) pass through untouched.
String normalizeForSearch(String input) {
  if (input.isEmpty) return '';

  final folded = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    folded.writeCharCode(_preLowerFolds[unit] ?? unit);
  }

  final lowered = folded.toString().toLowerCase();

  final out = StringBuffer();
  var pendingSpace = false;
  for (var i = 0; i < lowered.length; i++) {
    final unit = lowered.codeUnitAt(i);
    if (_isWhitespace(unit)) {
      // Only a space that is followed by more content survives; leading
      // whitespace never sets the flag because the buffer is still empty.
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) {
      out.writeCharCode(0x20);
      pendingSpace = false;
    }
    out.writeCharCode(_diacriticFolds[unit] ?? unit);
  }
  return out.toString();
}
