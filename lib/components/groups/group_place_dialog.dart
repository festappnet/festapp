import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/inventory/views/place_search_dialog.dart';
import 'package:fstapp/components/inventory/views/quick_search_dialog.dart';
import 'package:fstapp/components/map/place_model.dart';

class UseCustomGroupLocationAction {
  const UseCustomGroupLocationAction();
}

class RemoveGroupPlaceAction {
  const RemoveGroupPlaceAction();
}

/// Presents the two distinct place concepts explicitly: linking the group to
/// a shared catalog place, or creating/editing its own private map point.
class GroupPlaceDialog extends StatelessWidget {
  final List<PlaceModel> places;
  final PlaceModel? currentPlace;

  const GroupPlaceDialog({
    super.key,
    required this.places,
    required this.currentPlace,
  });

  Future<void> _chooseExistingPlace(BuildContext context) async {
    final currentCatalogPlace =
        currentPlace?.isPrivateGroupLocation == false ? currentPlace : null;
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => PlaceSearchDialog(
        allPlaces: places,
        currentPlace: currentCatalogPlace,
      ),
    );
    if (!context.mounted) return;
    if (result is PlaceModel) {
      Navigator.of(context).pop(result);
    } else if (result is UnassignAction) {
      Navigator.of(context).pop(const RemoveGroupPlaceAction());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(GroupsStrings.placeDialogTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (currentPlace?.title?.isNotEmpty == true) ...[
              Text(
                GroupsStrings.currentPlace(currentPlace!.title!),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(GroupsStrings.chooseExistingPlace),
                subtitle: Text(GroupsStrings.chooseExistingPlaceHint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseExistingPlace(context),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.add_location_alt_outlined),
                title: Text(GroupsStrings.customGroupLocation),
                subtitle: Text(GroupsStrings.customGroupLocationHint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .pop(const UseCustomGroupLocationAction()),
              ),
            ),
            if (currentPlace != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.link_off),
                label: Text(GroupsStrings.removePlace),
                onPressed: () =>
                    Navigator.of(context).pop(const RemoveGroupPlaceAction()),
              ),
            ],
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
