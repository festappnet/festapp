import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/occasion/occasion_creation_button.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/services/responsive_service.dart';
import 'package:intl/intl.dart';

/// A custom stateful widget for the picker UI with search functionality.
class ProjectPicker<T> extends StatefulWidget {
  final VoidCallback onDismiss;
  final List<T> items;
  final T? selectedItem;
  final String Function(T item) itemTitleBuilder;
  final void Function(T item) onItemSelected;
  final VoidCallback? onCreateNew;
  final VoidCallback? onCreateNewQuick;
  final String hintText;
  final String createNewText;
  final Object? Function(T item) itemIdBuilder;

  // A function to get a date from an item for sorting and display.
  final DateTime? Function(T item)? itemDateBuilder;
  final String? happeningNowText;
  final String? upcomingText;
  final String? pastText;
  final Object? Function(T item)? itemGroupIdBuilder;
  final String Function(T item)? itemGroupTitleBuilder;
  final String Function(T item)? itemSearchTextBuilder;
  final String? Function(T item)? itemDetailBuilder;
  final String? emptyText;
  final String? clearSearchText;

  const ProjectPicker({
    super.key,
    required this.onDismiss,
    required this.items,
    this.selectedItem,
    required this.itemTitleBuilder,
    required this.onItemSelected,
    this.onCreateNew,
    this.onCreateNewQuick,
    required this.hintText,
    required this.createNewText,
    required this.itemIdBuilder,
    this.itemDateBuilder,
    this.happeningNowText,
    this.upcomingText,
    this.pastText,
    this.itemGroupIdBuilder,
    this.itemGroupTitleBuilder,
    this.itemSearchTextBuilder,
    this.itemDetailBuilder,
    this.emptyText,
    this.clearSearchText,
  });

  @override
  State<ProjectPicker<T>> createState() => _ProjectPickerState<T>();
}

class _PickerGroupHeading {
  const _PickerGroupHeading(this.title, {this.separated = false});
  final String title;
  final bool separated;
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
    final now = DateTime.now();
    final groupId = widget.itemGroupIdBuilder;
    final groupTitle = widget.itemGroupTitleBuilder;
    final List<dynamic> display;
    if (groupId == null || groupTitle == null) {
      display = _datedItems(sourceItems, now);
    } else {
      final groups = <Object?, List<T>>{};
      for (final item in sourceItems) {
        groups.putIfAbsent(groupId(item), () => []).add(item);
      }
      final entries = groups.entries.toList()
        ..sort((a, b) {
          if (a.key == null && b.key != null) return 1;
          if (b.key == null && a.key != null) return -1;
          return groupTitle(a.value.first).compareTo(groupTitle(b.value.first));
        });
      display = [
        for (var i = 0; i < entries.length; i++) ...[
          _PickerGroupHeading(
            groupTitle(entries[i].value.first),
            separated: i > 0,
          ),
          ..._datedItems(entries[i].value, now),
        ],
      ];
    }
    setState(() => _displayItems = display);
  }

  List<dynamic> _datedItems(List<T> sourceItems, DateTime now) {
    if (widget.itemDateBuilder == null) return sourceItems;
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
      final endTime = (item is OccasionModel)
          ? (item.endTime ?? startTime)
          : startTime;

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
      final dateA = (a is OccasionModel)
          ? (a.endTime ?? widget.itemDateBuilder!(a)!)
          : widget.itemDateBuilder!(a)!;
      final dateB = (b is OccasionModel)
          ? (b.endTime ?? widget.itemDateBuilder!(b)!)
          : widget.itemDateBuilder!(b)!;
      return dateB.compareTo(dateA); // descending
    });

    List<dynamic> newDisplayList = [];
    if (presentItems.isNotEmpty) {
      if (widget.happeningNowText != null) {
        newDisplayList.add(widget.happeningNowText!);
      }
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

    return newDisplayList;
  }

  void _filterItems() {
    final query = _searchController.text;
    final List<T> filtered;
    if (query.isEmpty) {
      filtered = List.from(widget.items);
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      filtered = widget.items.where((item) {
        final date = widget.itemDateBuilder?.call(item);
        final searchable = [
          widget.itemTitleBuilder(item),
          if (date != null) DateFormat.yMd().format(date),
          if (widget.itemSearchTextBuilder != null)
            widget.itemSearchTextBuilder!(item),
        ].join(' ');
        final normalizedTitle = Utilities.removeDiacritics(
          searchable.toLowerCase(),
        );
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
      color: hintColor,
      fontWeight: FontWeight.normal,
    );
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
                        suffixIcon:
                            _searchController.text.isNotEmpty &&
                                widget.clearSearchText != null
                            ? IconButton(
                                tooltip: widget.clearSearchText,
                                icon: const Icon(Icons.close, size: iconSize),
                                onPressed: _searchController.clear,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Flexible(
            child: _displayItems.isEmpty && widget.emptyText != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(widget.emptyText!),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _displayItems.length,
                    itemBuilder: (context, index) {
                      final entry = _displayItems[index];

                      if (entry is _PickerGroupHeading) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (entry.separated)
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                entry.separated ? 12 : 20,
                                16,
                                0,
                              ),
                              child: Semantics(
                                header: true,
                                child: Text(
                                  entry.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      if (entry is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16.0,
                            16.0,
                            16.0,
                            8.0,
                          ),
                          child: Text(
                            entry,
                            style:
                                (ResponsiveService.isMobile(context)
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
                      final selected = widget.selectedItem;
                      final isSelected =
                          selected != null &&
                          widget.itemIdBuilder(item) ==
                              widget.itemIdBuilder(selected);

                      final date = widget.itemDateBuilder?.call(item);
                      final detail = widget.itemDetailBuilder?.call(item);
                      final labels = [
                        if (date != null) DateFormat.yMd().format(date),
                        if (detail != null && detail.isNotEmpty) detail,
                      ];
                      final subtitle = labels.isEmpty
                          ? null
                          : Text(
                              labels.join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: hintColor,
                              ),
                            );

                      return Semantics(
                        selected: isSelected,
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                          ),
                          title: Text(
                            widget.itemTitleBuilder(item),
                            style: titleTextStyle,
                          ),
                          subtitle: subtitle,
                          trailing: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: theme.primaryColor,
                                  size: iconSize,
                                )
                              : null,
                          onTap: () {
                            widget.onItemSelected(item);
                            widget.onDismiss();
                          },
                        ),
                      );
                    },
                  ),
          ),
          if (widget.onCreateNew != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1),
                OccasionCreationButton(
                  showChoices: widget.onCreateNewQuick != null,
                  onGuided: () {
                    widget.onDismiss();
                    widget.onCreateNew!();
                  },
                  onQuick: () {
                    widget.onDismiss();
                    (widget.onCreateNewQuick ?? widget.onCreateNew)!();
                  },
                  builder: (onPressed) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                    ),
                    onTap: onPressed,
                    title: Row(
                      children: [
                        Icon(Icons.add, color: iconColor, size: iconSize),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.createNewText,
                            style: titleTextStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
