import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/dialogs/dialogs_strings.dart';
import 'package:fstapp/styles/styles_config.dart';

class ResponsiveSearchDialog<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(T) itemBuilder;
  final bool Function(T, String) filter;
  final String? searchLabel;
  final Widget? suggestion;
  final Widget? failure;

  const ResponsiveSearchDialog({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.filter,
    this.searchLabel,
    this.suggestion,
    this.failure,
  });

  @override
  State<ResponsiveSearchDialog<T>> createState() =>
      _ResponsiveSearchDialogState<T>();
}

class _ResponsiveSearchDialogState<T> extends State<ResponsiveSearchDialog<T>> {
  final TextEditingController _controller = TextEditingController();
  List<T> _filteredItems = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _controller.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSearchChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _controller.text;
    setState(() {
      if (query.isEmpty) {
        _isSearching = false;
        _filteredItems = widget.items;
      } else {
        _isSearching = true;
        _filteredItems =
            widget.items.where((item) => widget.filter(item, query)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Decide if we want a full screen scaffolding or a dialog shape
        // For mobile (small screens), we prefer full screen.
        // For desktop (large screens), we prefer a dialog.
        final isMobile = constraints.maxWidth <
            StylesConfig
                .appMaxWidth; // Using appMaxWidth as a breakpoint or define a smaller one like 600

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.searchLabel ?? CommonStrings.search,
                  border: InputBorder.none,
                  hintStyle: const TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                    },
                  ),
              ],
            ),
            body: _buildList(),
          );
        } else {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

            // Limit the size of the dialog
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.search),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText:
                                  widget.searchLabel ?? CommonStrings.search,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                            },
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildList(),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(CommonStrings.storno),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildList() {
    if (!_isSearching && widget.suggestion != null) {
      // If we are not actively searching (or query is empty) and have a suggestion widget?
      // The original search_page behavior shows 'suggestion' when query is empty.
      // But typically we want to show all items if provided, or the suggestion.
      // Show all items if query is empty
      // Re-reading search_page logic: "showItemsOnEmpty" controls this.
      // In DialogHelper, showItemsOnEmpty: true. So we show items.
      // If items list is empty initially?
      if (_filteredItems.isEmpty && widget.failure != null) {
        return widget.failure!;
      }
    }

    if (_filteredItems.isEmpty) {
      return widget.failure ?? Center(child: Text(DialogsStrings.noResults));
    }

    return ListView.builder(
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        return widget.itemBuilder(_filteredItems[index]);
      },
    );
  }
}
