import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/views/place_search_dialog.dart';
import 'package:fstapp/components/inventory/views/quick_search_dialog.dart';
import 'package:festapp_core/map.dart';

/// A tappable form field that opens a searchable place picker
/// ([PlaceSearchDialog]) instead of a plain dropdown.
///
/// Use this everywhere a place is chosen (event edit, add-event, speaker
/// slots, …) so the selection is consistently searchable by name.
class PlacePickerField extends StatelessWidget {
  final List<PlaceModel> places;
  final int? selectedPlaceId;
  final ValueChanged<int?> onChanged;
  final String labelText;

  /// Shown when nothing is selected. Defaults to an em dash.
  final String? placeholder;

  const PlacePickerField({
    super.key,
    required this.places,
    required this.selectedPlaceId,
    required this.onChanged,
    required this.labelText,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final selected = places.firstWhereOrNull((p) => p.id == selectedPlaceId);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final result = await showDialog(
          context: context,
          builder: (_) => PlaceSearchDialog(
            allPlaces: places,
            currentPlace: selected,
          ),
        );
        if (result is PlaceModel) {
          onChanged(result.id);
        } else if (result is UnassignAction) {
          onChanged(null);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          suffixIcon: const Icon(Icons.search),
        ),
        child: Text(
          selected?.title ?? placeholder ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}
