import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/clipboard_entry.dart';
import 'tile_shared.dart';

/// Grid tile for [ClipboardEntryType.imageSet]: a wrapping strip of 48px
/// thumbnails (each individually pasteable) plus paste-all / delete
/// actions. Keyboard model: thumb 0 rides the externally-supplied focus
/// node so the "autofocus first entry" flow lands on it; Arrow keys walk
/// the grid, row-end ArrowRight hops to the action column and remembers
/// the origin so ArrowLeft returns to the same row.
class ImageSetTile extends StatefulWidget {
  const ImageSetTile({
    super.key,
    required this.entry,
    required this.onDelete,
    this.onImageTap,
    this.onPasteAll,
    this.autofocus = false,
    this.focusNode,
  });

  final ClipboardEntry entry;
  final VoidCallback onDelete;

  /// Invoked when the user activates a specific thumbnail (tap or Enter).
  final void Function(int imageIndex)? onImageTap;

  /// Paste-all trigger: writes every image in the set to the clipboard so
  /// apps that iterate pasteboard items pick them all up at once.
  final VoidCallback? onPasteAll;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<ImageSetTile> createState() => _ImageSetTileState();
}

class _ImageSetTileState extends State<ImageSetTile> with AdoptableTileFocus {
  final FocusNode _deleteFocus = FocusNode(
    debugLabel: 'entry-delete',
    skipTraversal: true,
  );
  final FocusNode _pasteAllFocus = FocusNode(
    debugLabel: 'entry-paste-all',
    skipTraversal: true,
  );

  /// Extra focus nodes for thumbnails 1..N-1. Thumbnail 0 uses [tileFocus]
  /// so the externally provided focusNode (for the "autofocus first tile"
  /// hotkey flow) drops straight onto it.
  final List<FocusNode> _extraThumbFocuses = [];

  /// Index of the row-end thumbnail the user stepped out of when hopping
  /// to paste-all / delete via ArrowRight. ArrowLeft from paste-all
  /// restores focus here so the user lands back on the row they came from
  /// instead of being teleported to the grid's tail.
  int? _originatingThumb;

  @override
  void initState() {
    super.initState();
    initTileFocus(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant ImageSetTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateTileFocus(oldWidget.focusNode, widget.focusNode);
  }

  @override
  void dispose() {
    disposeTileFocus();
    _deleteFocus.dispose();
    _pasteAllFocus.dispose();
    for (final f in _extraThumbFocuses) {
      f.dispose();
    }
    super.dispose();
  }

  /// Restores focus to the previously recorded origin thumb (set whenever
  /// the user stepped out of the grid via ArrowLeft/Right) or [fallback]
  /// when no origin is known or the origin is no longer in range (e.g. the
  /// imageSet shrunk between the hop-out and the hop-back).
  void _focusOriginThumbOr(List<FocusNode> thumbs, FocusNode fallback) {
    final origin = _originatingThumb;
    if (origin != null && origin >= 0 && origin < thumbs.length) {
      thumbs[origin].requestFocus();
    } else {
      fallback.requestFocus();
    }
  }

  List<FocusNode> _ensureThumbFocuses(int count) {
    while (_extraThumbFocuses.length < count - 1) {
      _extraThumbFocuses.add(
        FocusNode(debugLabel: 'entry-thumb-${_extraThumbFocuses.length + 1}'),
      );
    }
    while (_extraThumbFocuses.length > count - 1) {
      _extraThumbFocuses.removeLast().dispose();
    }
    return [tileFocus, ..._extraThumbFocuses];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytesList = widget.entry.imagesBytes ?? const <Uint8List>[];
    final thumbFocuses = _ensureThumbFocuses(bytesList.length);
    final canPasteAll = widget.onPasteAll != null && bytesList.isNotEmpty;

    // Keyboard row hops must match Wrap's actual layout, so derive the
    // column count from the real width — Wrap wraps (it never clips), and
    // a hardcoded count sends ArrowUp/Down to the wrong visual cell as
    // soon as the window is resized off the default. LayoutBuilder only
    // rebuilds on constraint changes, so there is no per-frame churn.
    return LayoutBuilder(
      builder: (context, constraints) {
        const thumbExtent = 48.0;
        const thumbSpacing = 4.0;
        // Mirror the row chrome below: horizontal padding (10+10), the
        // 4px gap and one or two 28px trailing buttons.
        final chrome = 20.0 + 4.0 + 28.0 + (canPasteAll ? 28.0 : 0.0);
        final wrapWidth = constraints.maxWidth - chrome;
        final columns = math.max(
          1,
          ((wrapWidth + thumbSpacing) / (thumbExtent + thumbSpacing)).floor(),
        );
        return _buildBody(
          context,
          theme: theme,
          scheme: scheme,
          bytesList: bytesList,
          thumbFocuses: thumbFocuses,
          canPasteAll: canPasteAll,
          columns: columns,
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme scheme,
    required List<Uint8List> bytesList,
    required List<FocusNode> thumbFocuses,
    required bool canPasteAll,
    required int columns,
  }) {
    void focusByRowOffset(int delta) {
      final primary = FocusManager.instance.primaryFocus;
      final i = thumbFocuses.indexOf(primary!);
      if (i < 0) return;
      final target = i + delta;
      if (target >= 0 && target < thumbFocuses.length) {
        thumbFocuses[target].requestFocus();
      } else {
        // Boundary: let the list-level directional traversal take over so
        // Up from the top row exits to the tile above, Down from the bottom
        // row exits to the tile below — mirrors single-tile behavior.
        primary.focusInDirection(
          delta < 0 ? TraversalDirection.up : TraversalDirection.down,
        );
      }
    }

    return CallbackShortcuts(
      bindings: {
        // Right/Left cycle linearly across thumbs → paste-all → delete so
        // every focusable in the tile is reachable without overthinking
        // grid wrap semantics.
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final primary = FocusManager.instance.primaryFocus;
          final i = thumbFocuses.indexOf(primary!);
          if (i >= 0) {
            // End of any visual row (or last thumb overall) hops to the
            // trailing button column so the user isn't forced to walk every
            // thumb before reaching paste-all / delete. Recording the
            // origin here is what lets ArrowLeft from paste-all return to
            // the same row instead of yanking focus to the grid's tail.
            final atRowEnd = (i + 1) % columns == 0;
            final atLast = i == thumbFocuses.length - 1;
            if (atRowEnd || atLast) {
              _originatingThumb = i;
              if (canPasteAll) {
                _pasteAllFocus.requestFocus();
              } else {
                _deleteFocus.requestFocus();
              }
            } else {
              thumbFocuses[i + 1].requestFocus();
            }
          } else if (primary == _pasteAllFocus) {
            _deleteFocus.requestFocus();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final primary = FocusManager.instance.primaryFocus;
          if (primary == _deleteFocus) {
            if (canPasteAll) {
              _pasteAllFocus.requestFocus();
            } else if (thumbFocuses.isNotEmpty) {
              // No paste-all between delete and the grid: fall back to the
              // row-end the user came from when known, otherwise the
              // grid's tail (matches the linear-step expectation).
              _focusOriginThumbOr(thumbFocuses, thumbFocuses.last);
            }
            return;
          }
          if (primary == _pasteAllFocus && thumbFocuses.isNotEmpty) {
            // Restore the row-end the user stepped out of so paste-all
            // round-trips don't yank focus to the grid's tail when the
            // user was on an earlier row.
            _focusOriginThumbOr(thumbFocuses, thumbFocuses.last);
            return;
          }
          final i = thumbFocuses.indexOf(primary!);
          if (i > 0) thumbFocuses[i - 1].requestFocus();
        },
        // Up/Down jump one row inside the grid; at grid edges they fall
        // through to cross-tile traversal.
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            focusByRowOffset(columns),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            focusByRowOffset(-columns),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < bytesList.length; i++)
                        _Thumbnail(
                          bytes: bytesList[i],
                          index: i,
                          count: bytesList.length,
                          focusNode: thumbFocuses[i],
                          autofocus: widget.autofocus && i == 0,
                          onActivate: () => widget.onImageTap?.call(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(
                      '${widget.entry.preview} · '
                      '${formatEntryTime(widget.entry.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (canPasteAll)
              IconButton(
                focusNode: _pasteAllFocus,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.content_paste_go, size: 16),
                tooltip: 'Hepsini yapıştır',
                onPressed: widget.onPasteAll,
                style: trailingIconStyle(scheme, scheme.primary),
              ),
            IconButton(
              focusNode: _deleteFocus,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Sil',
              onPressed: widget.onDelete,
              style: trailingIconStyle(scheme, scheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.bytes,
    required this.index,
    required this.count,
    required this.focusNode,
    required this.onActivate,
    this.autofocus = false,
  });

  final Uint8List bytes;

  /// Position within the imageSet — feeds the semantic label so a screen
  /// reader can tell N visually identical tap targets apart.
  final int index;
  final int count;
  final FocusNode focusNode;
  final VoidCallback onActivate;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Wrap in FocusableActionDetector so Enter/Space activate the focused
    // thumbnail. Using InkWell alone wouldn't pick up keyboard activation,
    // and Shortcuts on the parent would have to disambiguate which child is
    // focused — doing it per-child keeps the wiring local.
    return FocusableActionDetector(
      focusNode: focusNode,
      autofocus: autofocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onActivate();
            return null;
          },
        ),
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return Semantics(
            button: true,
            label: 'Resim ${index + 1} / $count — yapıştır',
            child: GestureDetector(
              onTap: onActivate,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: focused ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.all(1),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // The Semantics wrapper above is the announced node.
                      excludeFromSemantics: true,
                      // Decode at thumbnail scale — a 5MB Retina screenshot
                      // would otherwise pin a ~20MB full-resolution RGBA
                      // bitmap in the image cache to paint a 48px square.
                      // Height only: specifying both dimensions would decode
                      // to a distorted square instead of letting cover crop.
                      cacheHeight: (48 * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      errorBuilder: (ctx, _, _) => ColoredBox(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
