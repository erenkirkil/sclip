import 'package:flutter/material.dart';

import '../models/clipboard_entry.dart';
import '../providers/history_provider.dart';
import 'entry_tile.dart';

class HistoryList extends StatelessWidget {
  const HistoryList({
    super.key,
    required this.provider,
    required this.onEntryTap,
  });

  final HistoryProvider provider;
  final Future<void> Function(ClipboardEntry entry) onEntryTap;

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
        return ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = entries[i];
            return ClipboardEntryTile(
              key: ValueKey(e.id),
              entry: e,
              autofocus: i == 0,
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
              onDelete: () => provider.removeById(e.id),
            );
          },
        );
      },
    );
  }
}
