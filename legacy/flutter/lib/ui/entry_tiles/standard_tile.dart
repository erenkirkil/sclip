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
class const StandardEntryTile({
  super.key,
  required this.entry,
  required this.onTap,
  required this.onDelete,
  this.onTapPlain,
  this.onOpen,
  this.autofocus = false,
  this.focusNode,
}) extends StatefulWidget {
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
    final canOpen = widget.onOpen != null && widget.entry.type == .url;
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
                  borderRadius: BorderRadius.circular(5),
                  side: BorderSide(color: scheme.primary, width: 1.5),
                )
              : null,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          minVerticalPadding: 2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 1,
          ),
          minLeadingWidth: 0,
          horizontalTitleGap: 6,
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
          title: Row(
            crossAxisAlignment: .baseline,
            textBaseline: .alphabetic,
            children: [
              Expanded(
                child: Text(
                  widget.entry.preview,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: const TextStyle(fontSize: 11.5, height: 1.2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                formatEntryTime(widget.entry.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: .min,
            children: [
              if (canOpen)
                IconButton(
                  focusNode: _openFocus,
                  icon: const Icon(Icons.open_in_new, size: 13),
                  tooltip: 'Tarayıcıda aç',
                  onPressed: widget.onOpen,
                  style: trailingIconStyle(scheme, scheme.primary),
                ),
              IconButton(
                focusNode: _deleteFocus,
                icon: const Icon(Icons.close, size: 13),
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
class const _SafeSvg({required this.xml}) extends StatelessWidget {
  final String xml;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      xml,
      fit: .contain,
      placeholderBuilder: (_) => const Icon(Icons.image_outlined, size: 14),
      errorBuilder: (_, _, _) =>
          const Icon(Icons.broken_image_outlined, size: 14),
    );
  }
}

class const _Leading({required this.entry}) extends StatelessWidget {
  final ClipboardEntry entry;

  Widget _badge(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: thumbExtent,
      height: thumbExtent,
      alignment: .center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        icon,
        size: 14,
        color: scheme.onSurfaceVariant,
        semanticLabel: label,
      ),
    );
  }

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
              width: 20,
              height: 20,
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
        return _badge(context, Icons.palette, 'Renk');
      case .svg:
        final xml = entry.text;
        if (xml != null && xml.isNotEmpty) {
          return Semantics(
            label: 'SVG görsel',
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: thumbExtent,
                  height: thumbExtent,
                  child: _SafeSvg(xml: xml),
                ),
              ),
            ),
          );
        }
        return _badge(context, Icons.image_outlined, 'SVG görsel');
      case .image:
        final bytes = entry.imageBytes;
        if (bytes != null && bytes.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              bytes,
              width: thumbExtent,
              height: thumbExtent,
              fit: .cover,
              gaplessPlayback: true,
              semanticLabel: 'Resim',
              // Decode at thumbnail scale (see ImageSetTile's thumbnails) —
              // full-size bytes stay untouched for writeBack.
              cacheHeight:
                  (thumbExtent * MediaQuery.devicePixelRatioOf(context))
                      .round(),
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.image, size: 14, semanticLabel: 'Resim'),
            ),
          );
        }
        return _badge(context, Icons.image, 'Resim');
      case .imageSet:
        // imageSet uses its own tile body; _Leading shouldn't be rendered
        // for it, but keep a sensible fallback if it ever slips through.
        return _badge(context, Icons.collections_outlined, 'Resim grubu');
      case .url:
        return _badge(context, Icons.link, 'Bağlantı');
      case .files:
        return _badge(context, Icons.folder, 'Dosya');
      case .pdf:
        return _badge(context, Icons.picture_as_pdf, 'PDF');
      case .richText:
        return _badge(context, Icons.text_snippet_outlined, 'Biçimli metin');
      case .text:
        return _badge(context, Icons.notes, 'Metin');
    }
  }
}
