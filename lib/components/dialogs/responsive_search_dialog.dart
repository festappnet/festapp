import 'package:fstapp/widgets/app_dialog.dart';
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
  final Widget? emptyState;
  final String? description;

  const ResponsiveSearchDialog({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.filter,
    this.searchLabel,
    this.suggestion,
    this.failure,
    this.emptyState,
    this.description,
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
          return AppDialog.fullscreen(
              child: Scaffold(
            appBar: AppDialogAppBar(
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
            body: _buildBody(),
          ));
        } else {
          return AppDialog(
            // Limit the size of the dialog
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: AppDialogHeader(
                        title: Row(
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
                    )),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildBody(),
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

  Widget _buildBody() => Column(
        children: [
          if (widget.description != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.description!),
            ),
          Expanded(child: _buildList()),
        ],
      );

  Widget _buildList() {
    if (widget.items.isEmpty && !_isSearching && widget.emptyState != null) {
      return widget.emptyState!;
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
