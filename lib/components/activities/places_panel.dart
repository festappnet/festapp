// places_panel.dart
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'activities_component_strings.dart';
import 'activity_timeline_controller.dart';

class PlacesPanel extends StatelessWidget {
  final ActivityTimelineController controller;

  const PlacesPanel({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedFilter =
        Utilities.removeDiacritics(controller.placeFilter.toLowerCase());
    final filtered = controller.allPlaces
        .where((p) => Utilities.removeDiacritics((p.title ?? "").toLowerCase())
            .contains(normalizedFilter))
        .toList();
    final hintColor = controller.hintColor;
    final textColor = controller.textColor;
    final chipBgColor =
        controller.isDark ? Colors.blueGrey[700] : Colors.blueGrey[100];
    final chipTextColor =
        controller.isDark ? Colors.white.withOpacity(0.9) : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(2),
      color: controller.isDark ? Colors.grey[850] : Colors.grey[100],
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: TextField(
            style: TextStyle(fontSize: 12, color: textColor),
            decoration: InputDecoration(
              hintText: ActivitiesComponentStrings.hintSearchPlaces,
              hintStyle: TextStyle(color: hintColor, fontSize: 12),
              isDense: true,
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Icon(Icons.search, size: 14, color: hintColor),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
            ),
            onChanged: controller.onPlaceFilterChanged,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: filtered.map((p) {
                return Draggable<ActivityPlaceModel>(
                  data: p,
                  onDragStarted: controller.hideAssignmentDetailOverlay,
                  feedback: Material(
                    elevation: 3.0,
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: chipBgColor?.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        p.title ?? ActivitiesComponentStrings.textUnnamedPlace,
                        style: TextStyle(fontSize: 12, color: chipTextColor),
                      ),
                    ),
                  ),
                  child: Chip(
                    backgroundColor: chipBgColor,
                    label: Text(
                        p.title ?? ActivitiesComponentStrings.textUnnamedPlace,
                        style: TextStyle(fontSize: 11, color: chipTextColor)),
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }
}
