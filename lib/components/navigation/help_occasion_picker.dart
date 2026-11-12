import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/project_picker_widget.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';

/// The ordinary occasion switcher, with organizer context for cross-unit help.
class HelpOccasionPicker extends StatelessWidget {
  const HelpOccasionPicker({
    super.key,
    required this.occasions,
    required this.organizers,
    required this.onSelected,
    this.onCreateNew,
    required this.onDismiss,
    this.selectedLink,
    this.recentLink,
  });

  final List<OccasionModel> occasions;
  final List<UnitModel> organizers;
  final String? selectedLink, recentLink;
  final ValueChanged<OccasionModel> onSelected;
  final VoidCallback? onCreateNew;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final titles = <int, String>{
      for (final unit in organizers)
        if (unit.id != null && unit.title?.trim().isNotEmpty == true)
          unit.id!: unit.title!.trim(),
    };
    String title(OccasionModel item) => item.title ?? item.link ?? '';
    int? groupId(OccasionModel item) =>
        titles.containsKey(item.unit) ? item.unit : null;
    String organizer(OccasionModel item) =>
        titles[item.unit] ?? 'HelpNavigation.otherEvents'.tr();
    final selected = occasions
        .where((item) => item.link == selectedLink)
        .firstOrNull;
    return ProjectPicker<OccasionModel>(
      items: occasions,
      selectedItem: selected,
      itemIdBuilder: (item) => item.link,
      itemTitleBuilder: title,
      itemDateBuilder: (item) => item.startTime,
      itemGroupIdBuilder: groupId,
      itemGroupTitleBuilder: organizer,
      itemSearchTextBuilder: (item) => '${organizer(item)} ${item.link ?? ''}',
      itemDetailBuilder: (item) {
        final ambiguous =
            occasions
                .where(
                  (other) =>
                      groupId(other) == groupId(item) &&
                      title(other) == title(item) &&
                      DateUtils.isSameDay(other.startTime, item.startTime),
                )
                .length >
            1;
        return [
          if (ambiguous && item.link != null) item.link!,
          if (item.link == recentLink && item.link != selectedLink)
            'HelpNavigation.recentEvent'.tr(),
        ].join(' · ');
      },
      hintText: AdministrationStrings.findOccasionHint,
      createNewText: 'HelpNavigation.createEvent'.tr(),
      happeningNowText: CommonStrings.happeningNow,
      upcomingText: CommonStrings.upcomingEvents,
      pastText: CommonStrings.pastEvents,
      emptyText: occasions.isEmpty
          ? 'HelpNavigation.noEvents'.tr()
          : 'HelpNavigation.noMatches'.tr(),
      clearSearchText: 'HelpNavigation.clearSearch'.tr(),
      onItemSelected: onSelected,
      onCreateNew: onCreateNew,
      onDismiss: onDismiss,
    );
  }
}
