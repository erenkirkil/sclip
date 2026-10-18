import 'package:flutter/material.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';
import 'package:sclip/services/entry_filter.dart';
import 'package:sclip/ui/history_list.dart';
import 'package:sclip/ui/search_bar.dart';

/// Mirrors HomePage's body composition: the query field is a *sibling* of
/// HistoryList, never a descendant. HomePage builds its own
/// HistoryProvider internally, so keyboard/filter behaviour can only be
/// driven against a seeded history through a harness like this one.
class SearchHarness extends StatefulWidget {
  const SearchHarness({super.key, required this.provider, this.onEntryTap});

  final HistoryProvider provider;
  final void Function(ClipboardEntry entry)? onEntryTap;

  @override
  State<SearchHarness> createState() => SearchHarnessState();
}

class SearchHarnessState extends State<SearchHarness> {
  final TextEditingController controller = TextEditingController();
  final FocusNode searchFocus = FocusNode(debugLabel: 'harness-search');
  final FocusNode firstItemFocus = FocusNode(debugLabel: 'harness-first-item');
  String query = '';
  bool searchOpen = true;

  @override
  void dispose() {
    controller.dispose();
    searchFocus.dispose();
    firstItemFocus.dispose();
    super.dispose();
  }

  /// Drives the query without touching focus. tester.enterText() would
  /// steal focus from whatever tile a test just navigated to, which is
  /// exactly the state the filter tests need to observe.
  void setQuery(String value) => setState(() => query = value);

  void focusList() {
    if (firstItemFocus.context != null) firstItemFocus.requestFocus();
  }

  void focusSearchField() => searchFocus.requestFocus();

  void closeSearch() {
    controller.clear();
    setState(() {
      searchOpen = false;
      query = '';
    });
    focusList();
  }

  void submit() {
    final results = filterEntries(widget.provider.entries, query);
    if (results.isEmpty) return;
    widget.onEntryTap?.call(results.first);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            if (searchOpen)
              HistorySearchBar(
                controller: controller,
                focusNode: searchFocus,
                onChanged: setQuery,
                onSubmit: submit,
                onClose: closeSearch,
                onDownToList: focusList,
              ),
            Expanded(
              child: HistoryList(
                provider: widget.provider,
                query: query,
                onEntryTap: (
                  ClipboardEntry entry, {
                  int? imageIndex,
                  bool plainOnly = false,
                }) async {},
                onEntryOpen: (ClipboardEntry entry) async {},
                firstItemFocusNode: firstItemFocus,
                onArrowUpAtTop: searchOpen ? focusSearchField : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
