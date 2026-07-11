import 'package:flutter/material.dart';

import '../models/clipboard_entry.dart';
import 'entry_tiles/image_set_tile.dart';
import 'entry_tiles/standard_tile.dart';

/// Public tile facade used by HistoryList: dispatches to the standard
/// single-row tile or the imageSet grid tile. The two variants live in
/// `entry_tiles/` with their own state (focus nodes, grid navigation) —
/// keeping them separate means a 30-entry text history no longer allocates
/// imageSet-only state per tile.
class ClipboardEntryTile extends StatelessWidget {
  const ClipboardEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.onTapPlain,
    this.onOpen,
    this.onImageTap,
    this.onPasteAll,
    this.autofocus = false,
    this.focusNode,
  });

  final ClipboardEntry entry;
  final VoidCallback onTap;

  /// "Paste as plain text" — triggered by Shift+click / Shift+Enter on
  /// entries that have a text representation. Null hides the affordance.
  final VoidCallback? onTapPlain;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

  /// Invoked when the user activates a specific thumbnail on an
  /// [ClipboardEntryType.imageSet] tile (tap or Enter). Ignored for other
  /// entry types.
  final void Function(int imageIndex)? onImageTap;

  /// Paste-all trigger for [ClipboardEntryType.imageSet]: writes every image
  /// in the set to the clipboard as a multi-item payload so apps that iterate
  /// pasteboard items pick them all up at once.
  final VoidCallback? onPasteAll;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    if (entry.type == ClipboardEntryType.imageSet) {
      return ImageSetTile(
        entry: entry,
        onDelete: onDelete,
        onImageTap: onImageTap,
        onPasteAll: onPasteAll,
        autofocus: autofocus,
        focusNode: focusNode,
      );
    }
    return StandardEntryTile(
      entry: entry,
      onTap: onTap,
      onTapPlain: onTapPlain,
      onDelete: onDelete,
      onOpen: onOpen,
      autofocus: autofocus,
      focusNode: focusNode,
    );
  }
}
