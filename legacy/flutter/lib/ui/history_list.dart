import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/clipboard_entry.dart';
import '../providers/history_provider.dart';
import '../services/entry_filter.dart';
import 'entry_tile.dart';

class const HistoryList({
  super.key,
  required this.provider,
  required this.onEntryTap,
  required this.onEntryOpen,
  this.firstItemFocusNode,
  this.query = '',
  this.onArrowUpAtTop,
}) extends StatefulWidget {
  final HistoryProvider provider;
  final Future<void> Function(
    ClipboardEntry entry, {
    int? imageIndex,
    bool plainOnly,
  })
  onEntryTap;
  final Future<void> Function(ClipboardEntry entry) onEntryOpen;
  final FocusNode? firstItemFocusNode;

  /// Live search query. Applied through [filterEntries], a pure function:
  /// HistoryProvider's own list is never mutated, so the `onEvict` →
  /// temp-file-deletion side effect on removeAt/clear stays untouched.
  final String query;

  /// Invoked instead of directional traversal when ArrowUp is pressed
  /// while the *first* tile holds focus. HomePage passes a non-null
  /// callback only while the query bar is open; when it's null the old
  /// behaviour survives and ArrowUp climbs to the AppBar buttons.
  final VoidCallback? onArrowUpAtTop;

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
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Silindi: ${e.preview}',
        .ltr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final entries = filterEntries(widget.provider.entries, widget.query);
        if (entries.isEmpty) {
          // A live query that matches nothing is a different situation
          // from an empty history: "bir şey kopyala" would tell a user
          // with 30 entries to go copy something.
          final trimmed = widget.query.trim();
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                trimmed.isEmpty
                    ? 'Henüz içerik yok — bir şey kopyala'
                    : "'$trimmed' için sonuç yok",
                textAlign: .center,
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
          );
        }
        // Arrow keys are not part of the default Flutter traversal map — wire
        // them to directional focus so the list behaves like any native list.
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              FocusManager.instance.primaryFocus?.focusInDirection(.down);
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              final primary = FocusManager.instance.primaryFocus;
              final onAtTop = widget.onArrowUpAtTop;
              if (onAtTop != null &&
                  widget.firstItemFocusNode != null &&
                  primary == widget.firstItemFocusNode) {
                onAtTop();
                return;
              }
              primary?.focusInDirection(.up);
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              FocusManager.instance.primaryFocus?.focusInDirection(.right);
            },
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              FocusManager.instance.primaryFocus?.focusInDirection(.left);
            },
          },
          child: Builder(
            builder: (context) {
              final indexById = <String, int>{
                for (var i = 0; i < entries.length; i++) entries[i].id: i,
              };
              return ListView.separated(
                itemCount: entries.length,
                // Without this the delegate can't recognise a child that
                // moved: every keystroke of a live query re-inflates the
                // visible tiles, throwing away ImageSetTile's
                // _extraThumbFocuses / _originatingThumb and with them the
                // user's place in the grid (audit B-09). Note this is
                // findItemIndexCallback, not the deprecated
                // findChildIndexCallback — the latter wants child indices
                // (separators included) and warns on 3.44.8.
                findItemIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  return indexById[key.value];
                },
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return RepaintBoundary(
                    key: ValueKey(e.id),
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.delete): () =>
                            _delete(e),
                        const SingleActivator(
                          LogicalKeyboardKey.backspace,
                        ): () =>
                            _delete(e),
                      },
                      child: ClipboardEntryTile(
                        key: ValueKey(e.id),
                        entry: e,
                        autofocus: i == 0,
                        focusNode: i == 0 ? widget.firstItemFocusNode : null,
                        onTap: () => widget.onEntryTap(e),
                        // Shift+tık / Shift+Enter: düz metin olarak yapıştır.
                        onTapPlain: (e.text?.isNotEmpty ?? false)
                            ? () => widget.onEntryTap(e, plainOnly: true)
                            : null,
                        onImageTap: e.type == .imageSet
                            ? (index) => widget.onEntryTap(e, imageIndex: index)
                            : null,
                        onPasteAll: e.type == .imageSet
                            ? () => widget.onEntryTap(e)
                            : null,
                        onOpen: e.type == .url
                            ? () => widget.onEntryOpen(e)
                            : null,
                        onDelete: () => _delete(e),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
