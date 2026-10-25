import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:fstapp/components/users/widgets/profile_place_field.dart';

class CompanionAccommodationField extends StatelessWidget {
  const CompanionAccommodationField({
    super.key,
    required this.companion,
    required this.onOpenPlace,
  });

  final CompanionModel companion;
  final ValueChanged<int> onOpenPlace;

  @override
  Widget build(BuildContext context) {
    final place = companion.accommodationPlace;
    final title = place?.title?.trim() ?? '';
    return ProfilePlaceField(
      label: InventoryStrings.typeAccommodation,
      value: title.isEmpty ? InventoryStrings.accommodationNotSpecified : title,
      place: place,
      icon: Icons.hotel_outlined,
      onOpenPlace: onOpenPlace,
    );
  }
}
