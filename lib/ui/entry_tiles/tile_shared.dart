/// Bits shared by the standard and imageSet tile variants — kept together
/// so the two can't drift apart visually.
library;

import 'package:flutter/material.dart';

/// Focus/hover styling for the trailing icon buttons (open / paste-all /
/// delete). Solid high-alpha fills so keyboard focus on a *destructive*
/// action is unmistakable — deliberately louder than the tile's own focus
/// treatment.
ButtonStyle trailingIconStyle(ColorScheme scheme, Color tint) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return tint.withValues(alpha: 0.85);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return tint.withValues(alpha: 0.7);
      }
      return null;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused) ||
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return tint == scheme.error ? scheme.onError : scheme.onPrimary;
      }
      return null;
    }),
    overlayColor: WidgetStateProperty.all(Colors.transparent),
  );
}

/// Relative timestamp for tile subtitles ('şimdi', '5dk önce', '13:20').
/// HistoryList refreshes visible tiles once a minute so these don't go
/// stale on an idle window.
String formatEntryTime(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 60) return 'şimdi';
  if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
  if (diff.inHours < 24) return '${diff.inHours}sa önce';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Adopt-or-own management for the tile's primary [FocusNode]. HistoryList
/// hands the first tile an external node (the "autofocus first entry on
/// window show" flow); every other tile owns its node. Disposal must only
/// touch owned nodes — disposing the external one would break focus for
/// the whole window.
mixin AdoptableTileFocus<T extends StatefulWidget> on State<T> {
  late FocusNode tileFocus;
  bool _ownsTileFocus = false;

  void initTileFocus(FocusNode? external) {
    if (external != null) {
      tileFocus = external;
      _ownsTileFocus = false;
    } else {
      tileFocus = FocusNode(debugLabel: 'entry-tile');
      _ownsTileFocus = true;
    }
  }

  /// Call from didUpdateWidget when the external node reference changed
  /// (e.g. a tile stops being the first item after a reorder).
  void updateTileFocus(FocusNode? oldExternal, FocusNode? newExternal) {
    if (oldExternal == newExternal) return;
    if (_ownsTileFocus) tileFocus.dispose();
    tileFocus = newExternal ?? FocusNode(debugLabel: 'entry-tile');
    _ownsTileFocus = newExternal == null;
  }

  void disposeTileFocus() {
    if (_ownsTileFocus) tileFocus.dispose();
  }
}
