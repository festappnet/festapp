import 'package:material_ui/material_ui.dart';
import '../venue_layout_controller.dart';
import 'layout_strings.dart';

class LayoutFloorStyleField extends StatelessWidget {
  const LayoutFloorStyleField({super.key, required this.controller});
  final VenueLayoutController controller;
  @override
  Widget build(BuildContext context) {
    final value =
        controller.document.canvas['floorStyle'] as String? ?? 'plain';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('floor-style-$value'),
        initialValue: value,
        decoration: InputDecoration(
          labelText: VenueLayoutStrings.text(context, 'Floor appearance'),
          helperText: VenueLayoutStrings.text(
            context,
            'Floor patterns stay visible when zoomed out. A custom background takes precedence.',
          ),
          helperMaxLines: 2,
        ),
        items: [
          for (final entry in const {
            'plain': 'Plain floor',
            'wood': 'Wooden floor',
            'tile': 'Tiled floor',
            'carpet': 'Carpet',
          }.entries)
            DropdownMenuItem(value: entry.key, child: LayoutText(entry.value)),
        ],
        onChanged: controller.readOnly || controller.saving
            ? null
            : (next) => controller.apply(
                controller.document.copyWith(
                  canvas: {...controller.document.canvas, 'floorStyle': next!},
                ),
                label: 'Floor appearance',
              ),
      ),
    );
  }
}
