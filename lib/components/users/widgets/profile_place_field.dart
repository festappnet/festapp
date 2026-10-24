import 'package:flutter/material.dart';
import 'package:festapp_core/map.dart';

/// Read-only profile value that becomes a place link when a map place exists.
class ProfilePlaceField extends StatelessWidget {
  final String label;
  final String value;
  final PlaceModel? place;
  final IconData icon;
  final ValueChanged<int> onOpenPlace;

  const ProfilePlaceField({
    required this.label,
    required this.value,
    required this.place,
    required this.icon,
    required this.onOpenPlace,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final placeId = place?.id;
    final theme = Theme.of(context);
    final valueWidget = Text(
      value,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 17,
        height: 1,
        color: placeId == null ? null : theme.colorScheme.primary,
        decoration: placeId == null ? null : TextDecoration.underline,
        decorationColor: theme.colorScheme.primary,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: InputDecorator(
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.only(bottom: 3),
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: placeId == null
              ? valueWidget
              : InkWell(
                  onTap: () => onOpenPlace(placeId),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(icon, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Flexible(child: valueWidget),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
