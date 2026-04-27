import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/clipboard_entry.dart';

class ClipboardEntryTile extends StatefulWidget {
  const ClipboardEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.onOpen,
    this.onImageTap,
    this.onPasteAll,
    this.autofocus = false,
    this.focusNode,
  });

  final ClipboardEntry entry;
  final VoidCallback onTap;
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
  State<ClipboardEntryTile> createState() => _ClipboardEntryTileState();
}

class _ClipboardEntryTileState extends State<ClipboardEntryTile> {
  late FocusNode _tileFocus;
  // Trailing icon buttons are kept out of directional traversal so Arrow
  // Up/Down snap between tile primaries (the actual copy target) instead of
  // landing on a destructive action. Explicit Right/Left via our
  // CallbackShortcuts still reaches them via requestFocus.
  final FocusNode _openFocus = FocusNode(
    debugLabel: 'entry-open',
    skipTraversal: true,
  );
  final FocusNode _deleteFocus = FocusNode(
    debugLabel: 'entry-delete',
    skipTraversal: true,
  );
  final FocusNode _pasteAllFocus = FocusNode(
    debugLabel: 'entry-paste-all',
    skipTraversal: true,
  );
  bool _ownsTileFocus = false;

  /// Extra focus nodes for thumbnails 1..N-1 on imageSet tiles. Thumbnail 0
  /// uses [_tileFocus] so the externally provided focusNode (for the
  /// "autofocus first tile" hotkey flow) drops straight onto it.
  final List<FocusNode> _extraThumbFocuses = [];

  /// Index of the row-end thumbnail the user stepped out of when hopping
  /// to paste-all / delete via ArrowRight. ArrowLeft from paste-all
  /// restores focus here so the user lands back on the row they came from
  /// instead of being teleported to the grid's tail.
  int? _originatingThumb;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _tileFocus = widget.focusNode!;
      _ownsTileFocus = false;
    } else {
      _tileFocus = FocusNode(debugLabel: 'entry-tile');
      _ownsTileFocus = true;
    }
  }

  @override
  void didUpdateWidget(covariant ClipboardEntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsTileFocus) _tileFocus.dispose();
      _tileFocus = widget.focusNode ?? FocusNode(debugLabel: 'entry-tile');
      _ownsTileFocus = widget.focusNode == null;
    }
  }

  @override
  void dispose() {
    if (_ownsTileFocus) _tileFocus.dispose();
    _openFocus.dispose();
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

  void _focusFirstTrailing() {
    final canOpen =
        widget.onOpen != null && widget.entry.type == ClipboardEntryType.url;
    if (canOpen) {
      _openFocus.requestFocus();
    } else {
      _deleteFocus.requestFocus();
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
    return [_tileFocus, ..._extraThumbFocuses];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entry.type == ClipboardEntryType.imageSet) {
      return _buildImageSetTile(context);
    }
    return _buildStandardTile(context);
  }

  Widget _buildStandardTile(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Pick colors that read very differently so keyboard focus on the tile
    // (primary tint, "about to copy") is never confused with focus on the
    // delete button (error tint, "about to delete").
    final tileFocus = scheme.primary.withValues(alpha: 0.18);
    final tileHover = scheme.primary.withValues(alpha: 0.08);
    final canOpen =
        widget.onOpen != null && widget.entry.type == ClipboardEntryType.url;
    return CallbackShortcuts(
      bindings: {
        // Right from tile → first trailing button; from open → delete; from
        // delete → no-op (last focusable in row).
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final primary = FocusManager.instance.primaryFocus;
          if (primary == _tileFocus) {
            _focusFirstTrailing();
          } else if (primary == _openFocus) {
            _deleteFocus.requestFocus();
          }
        },
        // Left collapses back toward the tile so the user can return to
        // "about to copy" focus without tabbing through everything.
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final primary = FocusManager.instance.primaryFocus;
          if (primary == _deleteFocus && canOpen) {
            _openFocus.requestFocus();
          } else if (primary == _deleteFocus || primary == _openFocus) {
            _tileFocus.requestFocus();
          }
        },
      },
      child: ListTile(
        dense: true,
        autofocus: widget.autofocus,
        focusNode: _tileFocus,
        focusColor: tileFocus,
        hoverColor: tileHover,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        minLeadingWidth: 0,
        horizontalTitleGap: 14,
        onTap: widget.onTap,
        leading: _Leading(entry: widget.entry),
        title: Text(
          widget.entry.preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          _formatTime(widget.entry.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canOpen)
              IconButton(
                focusNode: _openFocus,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new, size: 16),
                tooltip: 'Tarayıcıda aç',
                onPressed: widget.onOpen,
                style: _trailingIconStyle(scheme, scheme.primary),
              ),
            IconButton(
              focusNode: _deleteFocus,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Sil',
              onPressed: widget.onDelete,
              style: _trailingIconStyle(scheme, scheme.error),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSetTile(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytesList = widget.entry.imagesBytes ?? const <Uint8List>[];
    final thumbFocuses = _ensureThumbFocuses(bytesList.length);
    final canPasteAll = widget.onPasteAll != null && bytesList.isNotEmpty;

    // Fixed grid width of 5 covers our min-window (300px). Hardcoding beats
    // LayoutBuilder churn here — a resize that drops us below 5 columns
    // would just clip the last thumb, which Wrap already handles gracefully.
    const columns = 5;

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
                      '${_formatTime(widget.entry.createdAt)}',
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
                style: _trailingIconStyle(scheme, scheme.primary),
              ),
            IconButton(
              focusNode: _deleteFocus,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Sil',
              onPressed: widget.onDelete,
              style: _trailingIconStyle(scheme, scheme.error),
            ),
          ],
        ),
      ),
    );
  }

  static ButtonStyle _trailingIconStyle(ColorScheme scheme, Color tint) {
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

  static String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return 'şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
    if (diff.inHours < 24) return '${diff.inHours}sa önce';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.bytes,
    required this.focusNode,
    required this.onActivate,
    this.autofocus = false,
  });

  final Uint8List bytes;
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
          return GestureDetector(
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
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Colors.black12),
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

/// Defense-in-depth render guard for SVG payloads. The ingestion path in
/// ClipboardService already rejects XXE/XInclude payloads before they
/// become entries, so this widget should never see malicious XML in
/// practice. It exists to catch the residual case where flutter_svg
/// itself throws on malformed-but-benign input (truncated XML, unknown
/// elements) — without it, one bad SVG in history could take the whole
/// list view down.
class _SafeSvg extends StatelessWidget {
  const _SafeSvg({required this.xml});

  final String xml;

  @override
  Widget build(BuildContext context) {
    try {
      return SvgPicture.string(
        xml,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const Icon(Icons.image_outlined),
      );
    } catch (_) {
      return const Icon(Icons.broken_image_outlined);
    }
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.entry});

  final ClipboardEntry entry;

  @override
  Widget build(BuildContext context) {
    switch (entry.type) {
      case ClipboardEntryType.color:
        final argb = entry.toArgb32();
        if (argb != null) {
          return Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(argb),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
          );
        }
        return const Icon(Icons.palette);
      case ClipboardEntryType.svg:
        final xml = entry.text;
        if (xml != null && xml.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(width: 48, height: 48, child: _SafeSvg(xml: xml)),
          );
        }
        return const Icon(Icons.image_outlined);
      case ClipboardEntryType.image:
        final bytes = entry.imageBytes;
        if (bytes != null && bytes.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              bytes,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Icon(Icons.image),
            ),
          );
        }
        return const Icon(Icons.image);
      case ClipboardEntryType.imageSet:
        // imageSet uses its own tile body; _Leading shouldn't be rendered
        // for it, but keep a sensible fallback if it ever slips through.
        return const Icon(Icons.collections_outlined);
      case ClipboardEntryType.url:
        return const Icon(Icons.link);
      case ClipboardEntryType.files:
        return const Icon(Icons.folder);
      case ClipboardEntryType.pdf:
        return const Icon(Icons.picture_as_pdf);
      case ClipboardEntryType.richText:
        return const Icon(Icons.text_snippet_outlined);
      case ClipboardEntryType.text:
        return const Icon(Icons.notes);
    }
  }
}
