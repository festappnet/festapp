import 'package:flutter/material.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/services/responsive_service.dart';
import 'package:intl/intl.dart';

/// A custom stateful widget for the picker UI with search functionality.
class ProjectPicker<T> extends StatefulWidget {
  final VoidCallback onDismiss;
  final List<T> items;
  final T selectedItem;
  final String Function(T item) itemTitleBuilder;
  final void Function(T item) onItemSelected;
  final VoidCallback? onCreateNew;
  final String hintText;
  final String createNewText;
  final Object? Function(T item) itemIdBuilder;

  // A function to get a date from an item for sorting and display.
  final DateTime? Function(T item)? itemDateBuilder;
  final String? happeningNowText;
  final String? upcomingText;
  final String? pastText;

  const ProjectPicker({
    super.key,
    required this.onDismiss,
    required this.items,
    required this.selectedItem,
    required this.itemTitleBuilder,
    required this.onItemSelected,
    this.onCreateNew,
    required this.hintText,
    required this.createNewText,
    required this.itemIdBuilder,
    this.itemDateBuilder,
    this.happeningNowText,
    this.upcomingText,
    this.pastText,
  });

  @override
  State<ProjectPicker<T>> createState() => _ProjectPickerState<T>();
}

class _ProjectPickerState<T> extends State<ProjectPicker<T>> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _displayItems = [];

  @override
  void initState() {
    super.initState();
    _processItems(widget.items);
    if (widget.hintText.isNotEmpty) {
      _searchController.addListener(_filterItems);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterItems);
    _searchController.dispose();
    super.dispose();
  }

  void _processItems(List<T> sourceItems) {
    if (widget.itemDateBuilder == null) {
      setState(() {
        _displayItems = sourceItems;
      });
      return;
    }

    final now = DateTime.now();
    final List<T> presentItems = [];
    final List<T> upcomingItems = [];
    final List<T> pastItems = [];
    final List<T> datelessItems = [];

    for (var item in sourceItems) {
      final startTime = widget.itemDateBuilder!(item);
      if (startTime == null) {
        datelessItems.add(item);
        continue;
      }
      final endTime = (item is OccasionModel) ? item.endTime! : startTime;

      if (startTime.isBefore(now) && endTime.isAfter(now)) {
        presentItems.add(item);
      } else if (startTime.isAfter(now)) {
        upcomingItems.add(item);
      } else {
        pastItems.add(item);
      }
    }

    upcomingItems.sort((a, b) {
      final dateA = widget.itemDateBuilder!(a)!;
      final dateB = widget.itemDateBuilder!(b)!;
      return dateA.compareTo(dateB);
    });

    pastItems.sort((a, b) {
      final dateA =
          (a is OccasionModel) ? a.endTime! : widget.itemDateBuilder!(a)!;
      final dateB =
          (b is OccasionModel) ? b.endTime! : widget.itemDateBuilder!(b)!;
      return dateB.compareTo(dateA); // descending
    });

    List<dynamic> newDisplayList = [];
    if (presentItems.isNotEmpty) {
      if (widget.happeningNowText != null)
        newDisplayList.add(widget.happeningNowText!);
      newDisplayList.addAll(presentItems);
    }
    if (upcomingItems.isNotEmpty) {
      if (widget.upcomingText != null) newDisplayList.add(widget.upcomingText!);
      newDisplayList.addAll(upcomingItems);
    }
    if (pastItems.isNotEmpty) {
      if (widget.pastText != null) newDisplayList.add(widget.pastText!);
      newDisplayList.addAll(pastItems);
    }
    if (datelessItems.isNotEmpty) {
      newDisplayList.addAll(datelessItems);
    }

    setState(() {
      _displayItems = newDisplayList;
    });
  }

  void _filterItems() {
    final query = _searchController.text;
    final List<T> filtered;
    if (query.isEmpty) {
      filtered = List.from(widget.items);
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      filtered = widget.items.where((item) {
        final normalizedTitle = Utilities.removeDiacritics(
            widget.itemTitleBuilder(item).toLowerCase());
        return normalizedTitle.contains(normalizedQuery);
      }).toList();
    }
    _processItems(filtered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final baseTextStyle = theme.textTheme.bodyMedium;
    final textColor = isDarkMode ? Colors.grey[300] : Colors.grey[800];
    final hintColor = isDarkMode ? Colors.grey[500] : Colors.grey[500];
    final iconColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];
    final titleTextStyle = baseTextStyle?.copyWith(color: textColor);
    final hintTextStyle = baseTextStyle?.copyWith(
        color: hintColor, fontWeight: FontWeight.normal);
    const iconSize = 20.0;

    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.hintText.isNotEmpty) ...[
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 16.0, right: 16.0),
              title: Row(
                children: [
                  Icon(Icons.search, color: iconColor, size: iconSize),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: !ResponsiveService.isMobile(context),
                      style: titleTextStyle,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: hintTextStyle,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _displayItems.length,
              itemBuilder: (context, index) {
                final entry = _displayItems[index];

                if (entry is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Text(
                      entry,
                      style: (ResponsiveService.isMobile(context)
                              ? theme.textTheme.labelMedium
                              : theme.textTheme.labelLarge)
                          ?.copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }

                final item = entry as T;
                final isSelected = widget.itemIdBuilder(item) ==
                    widget.itemIdBuilder(widget.selectedItem);

                Widget? subtitle;
                if (widget.itemDateBuilder != null) {
                  final date = widget.itemDateBuilder!(item);
                  if (date != null) {
                    subtitle = Text(
                      DateFormat('d. M. yyyy').format(date),
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: hintColor),
                    );
                  }
                }

                return ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.only(left: 16.0, right: 16.0),
                  title: Text(widget.itemTitleBuilder(item),
                      style: titleTextStyle),
                  subtitle: subtitle,
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: theme.primaryColor, size: iconSize)
                      : null,
                  onTap: () {
                    widget.onItemSelected(item);
                    widget.onDismiss();
                  },
                );
              },
            ),
          ),
          if (widget.onCreateNew != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.only(left: 16.0, right: 16.0),
                  onTap: () {
                    widget.onCreateNew!();
                    widget.onDismiss();
                  },
                  title: Row(
                    children: [
                      Icon(Icons.add, color: iconColor, size: iconSize),
                      const SizedBox(width: 12),
                      Text(widget.createNewText, style: titleTextStyle),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
