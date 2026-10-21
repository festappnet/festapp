import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/project_picker_widget.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'occasion_setup_strings.dart';

class OccasionSetupSourcePicker extends StatelessWidget {
  const OccasionSetupSourcePicker(
      {super.key,
      required this.sources,
      required this.selectedId,
      required this.label,
      required this.onChanged,
      this.unavailableLabel});
  final List<Map<String, dynamic>> sources;
  final int? selectedId;
  final String Function(Map<String, dynamic>) label;
  final ValueChanged<int?> onChanged;
  final String? unavailableLabel;

  void _pick(BuildContext context) {
    final items = sources
        .map((s) =>
            OccasionModel.fromJson(Map<String, dynamic>.from(s['occasion'])))
        .toList();
    String title(OccasionModel item) {
      final source =
          sources.firstWhere((s) => (s['occasion'] as Map)['id'] == item.id);
      return item.title?.trim().isNotEmpty == true
          ? item.title!.trim()
          : label(source);
    }

    String distinctTitle(OccasionModel item) {
      final text = title(item);
      if (items.where((other) => title(other) == text).length < 2) return text;
      return '$text · ${item.link?.isNotEmpty == true ? item.link : '#${item.id}'}';
    }

    showDialog<void>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
            title: Text(OccasionSetupStrings.copy('source')),
            content: SizedBox(
                height: 480,
                width: 360,
                child: ProjectPicker<OccasionModel>(
                  items: items,
                  selectedItem:
                      items.where((o) => o.id == selectedId).firstOrNull ??
                          OccasionModel(
                              isOpen: false, isHidden: true, isPromoted: false),
                  itemIdBuilder: (o) => o.id,
                  itemTitleBuilder: distinctTitle,
                  itemDateBuilder: (o) => o.startTime,
                  hintText: CommonStrings.search,
                  createNewText: OccasionSetupStrings.copy('fromScratch'),
                  happeningNowText: CommonStrings.happeningNow,
                  upcomingText: CommonStrings.upcomingEvents,
                  pastText: CommonStrings.pastEvents,
                  onItemSelected: (o) => onChanged(o.id),
                  onDismiss: () => Navigator.pop(dialogContext),
                ))));
  }

  String _selectedLabel() {
    final selected = sources
        .where((s) => (s['occasion'] as Map)['id'] == selectedId)
        .firstOrNull;
    return selected == null
        ? unavailableLabel ?? '#$selectedId'
        : label(selected);
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: true,
            groupValue: selectedId == null,
            title: Text(OccasionSetupStrings.story('newOccasion')),
            onChanged: (_) => onChanged(null)),
        RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: false,
            groupValue: selectedId == null,
            title: Text(OccasionSetupStrings.story('copyOccasion')),
            onChanged: sources.isEmpty ? null : (_) => _pick(context)),
        if (selectedId != null)
          OutlinedButton.icon(
              onPressed: sources.isEmpty ? null : () => _pick(context),
              icon: const Icon(Icons.search),
              label: Text(OccasionSetupStrings.copy('source'))),
        if (selectedId != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_selectedLabel())),
      ]));
}
