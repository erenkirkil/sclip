import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/clipboard_entry.dart';
import '../providers/history_provider.dart';
import 'entry_tile.dart';

class HistoryList extends StatefulWidget {
  const HistoryList({
    super.key,
    required this.provider,
    required this.onEntryTap,
    required this.onEntryOpen,
    this.firstItemFocusNode,
  });

  final HistoryProvider provider;
  final Future<void> Function(ClipboardEntry entry, {int? imageIndex})
  onEntryTap;
  final Future<void> Function(ClipboardEntry entry) onEntryOpen;
  final FocusNode? firstItemFocusNode;

  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList> {
  /// Relative timestamps ('şimdi', '5dk önce') are computed at build time;
  /// nothing else re-renders an idle list, so without this a tile stamped
  /// 'şimdi' still reads 'şimdi' an hour later (indefinitely on Windows —
  /// macOS used to be saved only by an incidental rebuild on window show).
  /// One rebuild a minute of ≤30 lazy tiles is negligible.
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  /// Shared delete path: announced for screen readers because the tile
  /// silently vanishing is the only other feedback. Copy/paste actions are
  /// deliberately not announced — the window hides and the paste itself is
  /// the feedback (a SnackBar here would render into a hidden window and
  /// flash stale on the next show).
  void _delete(ClipboardEntry e) {
    widget.provider.removeById(e.id);
    unawaited(
      SemanticsService.announce('Silindi: ${e.preview}', TextDirection.ltr),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        if (widget.provider.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Henüz içerik yok — bir şey kopyala',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final entries = widget.provider.entries;
        // Arrow keys are not part of the default Flutter traversal map — wire
        // them to directional focus so the list behaves like any native list.
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              FocusManager.instance.primaryFocus?.focusInDirection(
                TraversalDirection.down,
              );
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              FocusManager.instance.primaryFocus?.focusInDirection(
                TraversalDirection.up,
              );
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              FocusManager.instance.primaryFocus?.focusInDirection(
                TraversalDirection.right,
              );
            },
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              FocusManager.instance.primaryFocus?.focusInDirection(
                TraversalDirection.left,
              );
            },
          },
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              return RepaintBoundary(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.delete): () =>
                        _delete(e),
                    const SingleActivator(LogicalKeyboardKey.backspace): () =>
                        _delete(e),
                  },
                  child: ClipboardEntryTile(
                    key: ValueKey(e.id),
                    entry: e,
                    autofocus: i == 0,
                    focusNode: i == 0 ? widget.firstItemFocusNode : null,
                    onTap: () => widget.onEntryTap(e),
                    onImageTap: e.type == ClipboardEntryType.imageSet
                        ? (index) => widget.onEntryTap(e, imageIndex: index)
                        : null,
                    onPasteAll: e.type == ClipboardEntryType.imageSet
                        ? () => widget.onEntryTap(e)
                        : null,
                    onOpen: e.type == ClipboardEntryType.url
                        ? () => widget.onEntryOpen(e)
                        : null,
                    onDelete: () => _delete(e),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
