import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Query field for the clipboard history.
///
/// Mounted by HomePage as a *sibling* of HistoryList, never inside it:
/// `history_list.dart:120-126` binds both `Delete` and `Backspace` to an
/// undo-less `removeById` on every tile, and a `CallbackShortcuts` is an
/// ancestor Focus node for everything nested under it. A text field placed
/// in that subtree would erase a history entry on every correction the
/// user types. Keeping it outside makes that impossible by construction
/// rather than by a runtime guard someone can regress (design doc K-03).
class const HistorySearchBar({
  super.key,
  required this.controller,
  required this.focusNode,
  required this.onChanged,
  required this.onSubmit,
  required this.onClose,
  required this.onDownToList,
}) extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// Enter: paste the first result and hide the window — the same action
  /// as activating the top tile, without a trip through the list.
  final VoidCallback onSubmit;

  /// Esc or the trailing X: clear the query, close the bar, hand focus
  /// back to the list.
  final VoidCallback onClose;

  /// ArrowDown: move the keyboard into the first visible result. Bound
  /// here so it beats DefaultTextEditingShortcuts, which would otherwise
  /// consume it as "caret to the adjacent line".
  final VoidCallback onDownToList;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      child: CallbackShortcuts(
        // Bound here, wrapping the field, rather than up in HomePage's
        // Shortcuts: key dispatch walks *up* the focus chain, so a binding
        // this close to the TextField beats WidgetsApp's
        // DefaultTextEditingShortcuts (which maps Escape to DismissIntent).
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
          const SingleActivator(LogicalKeyboardKey.arrowDown): onDownToList,
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: .search,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
          style: const TextStyle(fontSize: 11.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            hintText: 'Geçmişte ara',
            hintStyle: const TextStyle(fontSize: 11.5),
            prefixIcon: const Icon(Icons.search, size: 14),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 26,
              minHeight: 24,
            ),
            suffixIcon: IconButton(
              tooltip: 'Aramayı kapat',
              icon: const Icon(Icons.close, size: 13),
              // 24×24 clears WCAG 2.5.8's 24×24 floor.
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: .zero,
              onPressed: onClose,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 26,
              minHeight: 24,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: .none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
          ),
        ),
      ),
    );
  }
}
