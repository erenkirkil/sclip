import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/clipboard_entry.dart';
import 'tile_shared.dart';

/// Single-row tile for every entry type except imageSet (which has its own
/// grid body in ImageSetTile). Keyboard model: the tile itself is the
/// directional-traversal target; ArrowRight/Left step into and out of the
/// trailing action buttons, which are skipTraversal so Up/Down snap between
/// tile primaries instead of landing on a destructive action.
class StandardEntryTile extends StatefulWidget {
  const StandardEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.onTapPlain,
    this.onOpen,
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
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<StandardEntryTile> createState() => _StandardEntryTileState();
}

class _StandardEntryTileState extends State<StandardEntryTile>
    with AdoptableTileFocus {
  final FocusNode _openFocus = FocusNode(
    debugLabel: 'entry-open',
    skipTraversal: true,
  );
  final FocusNode _deleteFocus = FocusNode(
    debugLabel: 'entry-delete',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    initTileFocus(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant StandardEntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateTileFocus(oldWidget.focusNode, widget.focusNode);
  }

  @override
  void dispose() {
    disposeTileFocus();
    _openFocus.dispose();
    _deleteFocus.dispose();
    super.dispose();
  }

  void _focusFirstTrailing(bool canOpen) {
    if (canOpen) {
      _openFocus.requestFocus();
    } else {
      _deleteFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Pick colors that read very differently so keyboard focus on the tile
    // (primary tint, "about to copy") is never confused with focus on the
    // delete button (error tint, "about to delete").
    final tileFocusColor = scheme.primary.withValues(alpha: 0.18);
    final tileHover = scheme.primary.withValues(alpha: 0.08);
    final canOpen =
        widget.onOpen != null && widget.entry.type == ClipboardEntryType.url;
    return CallbackShortcuts(
      bindings: {
        // Right from tile → first trailing button; from open → delete; from
        // delete → no-op (last focusable in row).
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final primary = FocusManager.instance.primaryFocus;
          if (primary == tileFocus) {
            _focusFirstTrailing(canOpen);
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
            tileFocus.requestFocus();
          }
        },
        // Shift+Enter: paste as plain text. Plain Enter stays with
        // ListTile's default activation (SingleActivator matches
        // modifier-less only, so the two never collide).
        if (widget.onTapPlain != null)
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () {
            if (FocusManager.instance.primaryFocus == tileFocus) {
              widget.onTapPlain!();
            }
          },
      },
      // ListenableBuilder so the focus ring below tracks keyboard focus —
      // the 18%-alpha focusColor tint alone is ~1.3:1 against the resting
      // row, far under the 3:1 WCAG non-text minimum for the app's primary
      // keyboard target.
      child: ListenableBuilder(
        listenable: tileFocus,
        builder: (context, _) => ListTile(
          dense: true,
          autofocus: widget.autofocus,
          focusNode: tileFocus,
          focusColor: tileFocusColor,
          hoverColor: tileHover,
          shape: tileFocus.hasFocus
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: scheme.primary, width: 2),
                )
              : null,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          minLeadingWidth: 0,
          horizontalTitleGap: 14,
          onTap: () {
            // Shift+click = paste as plain text (markup stripped).
            if (widget.onTapPlain != null &&
                HardwareKeyboard.instance.isShiftPressed) {
              widget.onTapPlain!();
            } else {
              widget.onTap();
            }
          },
          leading: _Leading(entry: widget.entry),
          title: Text(
            widget.entry.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            formatEntryTime(widget.entry.createdAt),
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
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  tooltip: 'Tarayıcıda aç',
                  onPressed: widget.onOpen,
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
      ),
    );
  }
}

/// Render guard for SVG payloads. The ingestion path in ClipboardService
/// already rejects XXE/XInclude payloads before they become entries; this
/// handles the residual case of malformed-but-benign input (truncated
/// XML, unknown elements). XML parsing happens *asynchronously* during
/// resolve — a try/catch around the constructor can never fire — so
/// errorBuilder is the mechanism that actually catches a failed parse.
class _SafeSvg extends StatelessWidget {
  const _SafeSvg({required this.xml});

  final String xml;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      xml,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => const Icon(Icons.image_outlined),
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.entry});

  final ClipboardEntry entry;

  @override
  Widget build(BuildContext context) {
    // Every branch carries a semantic label: the tile title announces only
    // preview + timestamp, so without these the entry *type* is conveyed
    // purely visually (a color entry reads as a bare hex string, richText
    // and text are indistinguishable to a screen reader).
    switch (entry.type) {
      case .color:
        final argb = entry.toArgb32();
        if (argb != null) {
          return Semantics(
            label: 'Renk',
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(argb),
                borderRadius: BorderRadius.circular(4),
                // Theme-derived: white24 was invisible around a light
                // swatch (e.g. #ffffff) on the light surface.
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          );
        }
        return const Icon(Icons.palette, semanticLabel: 'Renk');
      case .svg:
        final xml = entry.text;
        if (xml != null && xml.isNotEmpty) {
          return Semantics(
            label: 'SVG görsel',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(width: 48, height: 48, child: _SafeSvg(xml: xml)),
            ),
          );
        }
        return const Icon(Icons.image_outlined, semanticLabel: 'SVG görsel');
      case .image:
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
              semanticLabel: 'Resim',
              // Decode at thumbnail scale (see ImageSetTile's thumbnails) —
              // full-size bytes stay untouched for writeBack.
              cacheHeight: (48 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.image, semanticLabel: 'Resim'),
            ),
          );
        }
        return const Icon(Icons.image, semanticLabel: 'Resim');
      case .imageSet:
        // imageSet uses its own tile body; _Leading shouldn't be rendered
        // for it, but keep a sensible fallback if it ever slips through.
        return const Icon(
          Icons.collections_outlined,
          semanticLabel: 'Resim grubu',
        );
      case .url:
        return const Icon(Icons.link, semanticLabel: 'Bağlantı');
      case .files:
        return const Icon(Icons.folder, semanticLabel: 'Dosya');
      case .pdf:
        return const Icon(Icons.picture_as_pdf, semanticLabel: 'PDF');
      case .richText:
        return const Icon(
          Icons.text_snippet_outlined,
          semanticLabel: 'Biçimli metin',
        );
      case .text:
        return const Icon(Icons.notes, semanticLabel: 'Metin');
    }
  }
}
