import 'package:flutter/material.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'inventory_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class QuickSearchDialog<T> extends StatefulWidget {
  final String title;
  final List<T> allItems;
  final T? currentItem;
  final String Function(T) getItemTitle;
  final bool Function(T, T) compareItems;

  const QuickSearchDialog({
    super.key,
    required this.title,
    required this.allItems,
    this.currentItem,
    required this.getItemTitle,
    required this.compareItems,
  });

  @override
  State<QuickSearchDialog<T>> createState() => _QuickSearchDialogState<T>();
}

class _QuickSearchDialogState<T> extends State<QuickSearchDialog<T>> {
  final _searchController = TextEditingController();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.allItems
      ..sort(
          (a, b) => widget.getItemTitle(a).compareTo(widget.getItemTitle(b)));
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredItems = List.from(widget.allItems)
          ..sort((a, b) =>
              widget.getItemTitle(a).compareTo(widget.getItemTitle(b)));
      });
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      setState(() {
        _filteredItems = widget.allItems.where((item) {
          final normalizedName = Utilities.removeDiacritics(
              widget.getItemTitle(item).toLowerCase());
          return normalizedName.contains(normalizedQuery);
        }).toList();
      });
    }
  }

  void _selectAndPop(Object? result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 0),
      content: SizedBox(
        width: 350,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: InventoryStrings.searchDialogHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (widget.currentItem != null) ...[
                    ListTile(
                      title: Text(InventoryStrings.searchDialogUnassign),
                      leading: const Icon(Icons.clear),
                      onTap: () => _selectAndPop(UnassignAction()),
                    ),
                    const Divider(height: 1),
                  ],
                  ..._filteredItems.map((item) {
                    return ListTile(
                      title: Text(widget.getItemTitle(item)),
                      selected: widget.currentItem != null &&
                          widget.compareItems(widget.currentItem as T, item),
                      onTap: () => _selectAndPop(item),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
      ],
    );
  }
}

/// A sentinel class to indicate the unassign action in the dialog.
class UnassignAction {}
