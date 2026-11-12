import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/navigation/help_occasion_picker.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/user_strings.dart';

class MyEventsOverview extends StatelessWidget {
  const MyEventsOverview({
    super.key,
    required this.occasions,
    required this.units,
    required this.canCreate,
    required this.onCreate,
    required this.onOpen,
    required this.onOpenUnit,
  });
  final List<OccasionModel> occasions;
  final List<UnitModel> units;
  final bool canCreate;
  final VoidCallback onCreate;
  final ValueChanged<OccasionModel> onOpen;
  final ValueChanged<UnitModel> onOpenUnit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          UserStrings.myEvents,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
      if (units.isNotEmpty)
        SizedBox(
          height: 160,
          child: ListView(
            children: [
              for (final unit in units)
                ListTile(
                  title: Text(unit.title ?? '${unit.id}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpenUnit(unit),
                ),
            ],
          ),
        ),
      Expanded(
        child: HelpOccasionPicker(
          occasions: occasions,
          organizers: units,
          emptyText: CommonStrings.noEventsFound,
          onSelected: onOpen,
          onCreateNew: canCreate ? onCreate : null,
          // This picker is a page body here, not a modal to dismiss.
          onDismiss: () {},
        ),
      ),
    ],
  );
}
