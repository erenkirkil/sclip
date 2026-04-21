import 'package:flutter/material.dart';

import '../models/clipboard_entry.dart';

class ClipboardEntryTile extends StatelessWidget {
  const ClipboardEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.autofocus = false,
  });

  final ClipboardEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      autofocus: autofocus,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      minLeadingWidth: 0,
      horizontalTitleGap: 14,
      onTap: onTap,
      leading: _Leading(entry: entry),
      title: Text(
        entry.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        _formatTime(entry.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.hintColor,
          fontSize: 11,
        ),
      ),
      trailing: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.close, size: 16),
        tooltip: 'Sil',
        onPressed: onDelete,
      ),
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
      case ClipboardEntryType.url:
        return const Icon(Icons.link);
      case ClipboardEntryType.files:
        return const Icon(Icons.folder);
      case ClipboardEntryType.text:
        return const Icon(Icons.notes);
    }
  }
}
