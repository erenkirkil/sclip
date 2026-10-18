/// Bits shared by the standard and imageSet tile variants — kept together
/// so the two can't drift apart visually.
library;

import 'package:flutter/material.dart';

/// Edge length of a tile thumbnail (standard tile leading, imageSet grid
/// cell). Compacted to 24px for the 260×340 half-scale v2 window.
const double kTileThumbExtent = 24.0;
const double thumbExtent = kTileThumbExtent;

/// Grid gap between thumbnails in [ImageSetTile].
const double thumbSpacing = 3.0;

/// Hit-target edge length for the trailing tile actions (open / paste-all /
/// delete). Matches WCAG 2.5.8's 24x24 floor.
const double kTileActionHitExtent = 24.0;
const double trailingButtonExtent = kTileActionHitExtent;

/// Vertical breathing room a tile keeps above and below its content.
const double kTileRowPadding = 2.0;

/// Floor for a standard tile's row height.
const double kTileMinHeight = kTileThumbExtent + 2 * kTileRowPadding;

/// Decode height for thumbnail bitmaps, in device pixels.
int tileCacheHeight(double devicePixelRatio) =>
    (kTileThumbExtent * devicePixelRatio).round();

/// Focus/hover styling for the trailing icon buttons (open / paste-all /
/// delete). Solid high-alpha fills so keyboard focus on a *destructive*
/// action is unmistakable — deliberately louder than the tile's own focus
/// treatment.
ButtonStyle trailingIconStyle(ColorScheme scheme, Color tint) {
  return ButtonStyle(
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    minimumSize: const WidgetStatePropertyAll(
      Size.square(trailingButtonExtent),
    ),
    maximumSize: const WidgetStatePropertyAll(
      Size.square(trailingButtonExtent),
    ),
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
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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

  /// Owned nodes replaced by [updateTileFocus]. They are deliberately not
  /// disposed inline: under a live search query "first item" changes on
  /// every keystroke, so this path runs constantly, and the node being
  /// retired may still hold primary focus at that moment. Disposing it
  /// detaches it from the tree and drops focus to the enclosing scope,
  /// which kills arrow-key navigation for the whole window. A handful of
  /// FocusNodes held until [disposeTileFocus] is the cheap side of that
  /// trade.
  final List<FocusNode> _retiredTileFocuses = <FocusNode>[];

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
    // Read before the swap: this State's didUpdateWidget runs before the
    // child Focus widget re-attaches, so the old node is still the one
    // holding focus here.
    final hadFocus = tileFocus.hasFocus;
    if (_ownsTileFocus) {
      _retiredTileFocuses.add(tileFocus);
    }
    tileFocus = newExternal ?? FocusNode(debugLabel: 'entry-tile');
    _ownsTileFocus = newExternal == null;
    if (!hadFocus) return;
    // Same entry, different node — put the keyboard back where the user
    // left it. Deferred because the replacement isn't attached to the
    // tree until this frame's build completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tileFocus.requestFocus();
    });
  }

  void disposeTileFocus() {
    if (_ownsTileFocus) tileFocus.dispose();
    for (final node in _retiredTileFocuses) {
      node.dispose();
    }
    _retiredTileFocuses.clear();
  }
}
