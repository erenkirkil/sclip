import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/clipboard_entry.dart';
import '../providers/history_provider.dart';
import 'entry_tile.dart';

class HistoryList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        if (provider.isEmpty) {
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
        final entries = provider.entries;
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
                        provider.removeById(e.id),
                    const SingleActivator(LogicalKeyboardKey.backspace): () =>
                        provider.removeById(e.id),
                  },
                  child: ClipboardEntryTile(
                    key: ValueKey(e.id),
                    entry: e,
                    autofocus: i == 0,
                    focusNode: i == 0 ? firstItemFocusNode : null,
                    onTap: () async {
                      await onEntryTap(e);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 1),
                            content: Text('Kopyalandı: ${e.preview}'),
                          ),
                        );
                    },
                    onImageTap: e.type == ClipboardEntryType.imageSet
                        ? (index) async {
                            await onEntryTap(e, imageIndex: index);
                            if (!context.mounted) return;
                            final count = e.imagesBytes?.length ?? 0;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  duration: const Duration(seconds: 1),
                                  content: Text(
                                    'Kopyalandı: Resim ${index + 1} / $count',
                                  ),
                                ),
                              );
                          }
                        : null,
                    onPasteAll: e.type == ClipboardEntryType.imageSet
                        ? () async {
                            await onEntryTap(e);
                            if (!context.mounted) return;
                            final count = e.imagesBytes?.length ?? 0;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  duration: const Duration(seconds: 1),
                                  content: Text(
                                    'Kopyalandı: $count resim (hepsi)',
                                  ),
                                ),
                              );
                          }
                        : null,
                    onOpen: e.type == ClipboardEntryType.url
                        ? () => onEntryOpen(e)
                        : null,
                    onDelete: () => provider.removeById(e.id),
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
