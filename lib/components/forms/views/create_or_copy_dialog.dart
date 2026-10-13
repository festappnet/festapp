import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/services/utilities_all.dart';
import '../form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class CreateOrCopyFormDialog extends StatefulWidget {
  final List<FormModel> existingForms;

  const CreateOrCopyFormDialog({super.key, required this.existingForms});

  @override
  State<CreateOrCopyFormDialog> createState() => _CreateOrCopyFormDialogState();
}

class _CreateOrCopyFormDialogState extends State<CreateOrCopyFormDialog> {
  final _searchController = TextEditingController();
  late final FocusNode _focusNode;
  List<dynamic> _groupedAndFilteredForms = [];

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _filterAndGroupForms();
    _searchController.addListener(_filterAndGroupForms);

    // Add a short delay to allow the dialog animation to complete before focusing.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        // Check if the widget is still in the tree before requesting focus.
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterAndGroupForms);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filterAndGroupForms() {
    final query = _searchController.text;
    List<FormModel> tempFilteredForms;

    if (query.isEmpty) {
      tempFilteredForms = widget.existingForms;
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      tempFilteredForms = widget.existingForms.where((form) {
        final normalizedTitle =
            Utilities.removeDiacritics((form.title ?? "").toLowerCase());
        final normalizedOccasionTitle = Utilities.removeDiacritics(
            (form.occasionModel?.title ?? "").toLowerCase());
        return normalizedTitle.contains(normalizedQuery) ||
            normalizedOccasionTitle.contains(normalizedQuery);
      }).toList();
    }

    // Sort by occasion start time descending (newest first)
    tempFilteredForms.sort((a, b) {
      final dateA = a.occasionModel?.startTime ?? DateTime(0);
      final dateB = b.occasionModel?.startTime ?? DateTime(0);
      return dateB.compareTo(dateA);
    });

    final List<dynamic> newGroupedList = [];
    final now = DateTime.now();
    final List<FormModel> currentOccasions = [];
    final List<FormModel> upcomingOccasions = [];
    final List<FormModel> pastOccasions = [];
    final List<FormModel> datelessOccasions = [];

    for (var form in tempFilteredForms) {
      final occasion = form.occasionModel;
      if (occasion?.startTime == null || occasion?.endTime == null) {
        datelessOccasions.add(form);
        continue;
      }

      if (occasion!.startTime!.isBefore(now) &&
          occasion.endTime!.isAfter(now)) {
        currentOccasions.add(form);
      } else if (occasion.startTime!.isAfter(now)) {
        upcomingOccasions.add(form);
      } else {
        pastOccasions.add(form);
      }
    }

    if (currentOccasions.isNotEmpty) {
      newGroupedList.add(FormStrings.groupHappeningNow);
      newGroupedList.addAll(currentOccasions);
    }
    if (upcomingOccasions.isNotEmpty) {
      newGroupedList.add(FormStrings.groupUpcoming);
      newGroupedList.addAll(upcomingOccasions);
    }

    // Group past occasions by year
    if (pastOccasions.isNotEmpty) {
      final Map<int, List<FormModel>> pastByYear = {};
      for (final form in pastOccasions) {
        final year = form.occasionModel!.startTime!.year;
        (pastByYear[year] ??= []).add(form);
      }

      final sortedYears = pastByYear.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      for (final year in sortedYears) {
        newGroupedList.add(year.toString());
        newGroupedList.addAll(pastByYear[year]!);
      }
    }

    if (datelessOccasions.isNotEmpty) {
      newGroupedList.add(FormStrings.groupOther);
      newGroupedList.addAll(datelessOccasions);
    }

    setState(() {
      _groupedAndFilteredForms = newGroupedList;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FormStrings.createFormTitle),
      contentPadding: EdgeInsets.zero,
      // We wrap the content in a Container with BoxConstraints to make it responsive.
      content: Container(
        width: 450, // You can adjust this width as needed
        constraints: BoxConstraints(
          // Set a max height relative to the screen to avoid overflow.
          // 70% of the screen height is a reasonable maximum.
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // The Column will now fill the height of the Container.
          // This gives the Expanded widget a bounded height to fill.
          children: [
            // --- Part 1: Create New ---
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              leading: const Icon(Icons.add_circle_outline),
              title: Text(FormStrings.createNewBlankForm),
              onTap: () => Navigator.of(context).pop('CREATE_NEW'),
            ),
            const Divider(height: 1),

            // --- Part 2: Copy Existing ---
            // Header for the copy action
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
              child: Text(
                FormStrings.orCreateFromCopy,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            // Search Box now in the second part
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: FormStrings.searchFormsToCopy,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  isDense: true,
                ),
              ),
            ),
            // Expanded will now correctly fill the remaining space within the constrained Container.
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 0),
                itemCount: _groupedAndFilteredForms.length,
                itemBuilder: (context, index) {
                  final item = _groupedAndFilteredForms[index];
                  if (item is String) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    );
                  } else if (item is FormModel) {
                    final form = item;
                    final occasion = form.occasionModel;
                    final stats = form.stats;
                    final totalResponses = stats?.total ?? 0;
                    final theme = Theme.of(context);
                    final hintColor = theme.hintColor;

                    final currentLocale = context.locale.toString();

                    String subtitleText = occasion?.title ?? '---';
                    if (occasion?.startTime != null) {
                      final formattedDate = DateFormat.yMd(currentLocale)
                          .format(occasion!.startTime!);
                      subtitleText = '$subtitleText ($formattedDate)';
                    }

                    return ListTile(
                      leading: const Icon(Icons.article_outlined, size: 24),
                      title: Text(
                        form.toString(),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Tooltip(
                        message: FormStrings.numberOfResponsesTooltip(
                            totalResponses),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble, size: 16, color: hintColor),
                            const SizedBox(width: 4),
                            Text(
                              totalResponses.toString(),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: hintColor),
                            ),
                          ],
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(form),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
      ],
    );
  }
}
