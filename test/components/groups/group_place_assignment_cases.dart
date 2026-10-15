import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:trina_grid/trina_grid.dart';

void main() {
  group('group place ownership', () {
    test('hidden group place is a private group location', () {
      final place = PlaceModel(type: PlaceModel.groupType, isHidden: true);

      expect(place.isPrivateGroupLocation, isTrue);
    });

    test('visible existing place is never owned by the group', () {
      final place = PlaceModel(type: PlaceModel.groupType, isHidden: false);

      expect(place.isPrivateGroupLocation, isFalse);
    });

    test('hidden place of another type is not owned by the group', () {
      final place = PlaceModel(type: PlaceModel.WithoutValue, isHidden: true);

      expect(place.isPrivateGroupLocation, isFalse);
    });

    test('choosing a shared place clears pending custom-place persistence', () {
      final groupModel = UserGroupInfoModel(
        id: null,
        title: GroupsStrings.newGroup,
      );
      final customPlace = PlaceModel(
        type: PlaceModel.groupType,
        isHidden: true,
      );
      final existingPlace = PlaceModel(isHidden: false);

      groupModel.setPlaceForEditing(customPlace, savePlace: true);
      expect(groupModel.shouldSavePlace, isTrue);

      groupModel.setPlaceForEditing(existingPlace);
      expect(groupModel.place, same(existingPlace));
      expect(groupModel.shouldSavePlace, isFalse);
    });

    test('a selected place is accepted by the group grid and marks its row',
        () {
      final placeCell = TrinaCell(value: null);
      final groupModel = UserGroupInfoModel(
        id: Tb.user_group_info.id.hashCode,
        title: GroupsStrings.newGroup,
      );
      final row = TrinaRow(cells: {
        UserGroupInfoModel.modelReference: TrinaCell(value: groupModel),
        Tb.user_group_info.title: TrinaCell(value: groupModel.title),
        Tb.user_group_info.description: TrinaCell(value: null),
        Tb.user_group_info.place: placeCell,
      });
      final selectedPlace = PlaceModel(id: Tb.places.id.hashCode);
      var changed = false;
      final manager = TrinaGridStateManager(
        columns: [
          TrinaColumn(
            title: GroupsStrings.columnPlace,
            field: Tb.user_group_info.place,
            type: UserGroupInfoModel.placeColumnType(),
          ),
        ],
        rows: [row],
        gridFocusNode: FocusNode(),
        scroll: TrinaGridScrollController(),
        onChanged: (_) => changed = true,
      );

      manager.changeCellValue(placeCell, selectedPlace, force: true);

      expect(placeCell.value, same(selectedPlace));
      expect(row.state, TrinaRowState.updated);
      expect(changed, isTrue);
      final modelAtSaveBoundary =
          UserGroupInfoModel.fromPlutoJson(row.toJson());
      expect(modelAtSaveBoundary.place, same(selectedPlace));

      expect(modelAtSaveBoundary.place?.id, selectedPlace.id);

      final modelAfterReload = UserGroupInfoModel.fromJson({
        Tb.user_group_info.id: groupModel.id,
        Tb.user_group_info.title: groupModel.title,
        Tb.user_group_info.place: selectedPlace.id,
        Tb.places.table: selectedPlace.toJson(),
        Tb.user_groups.table: const [],
      });
      expect(modelAfterReload.place?.id, selectedPlace.id);
    });
  });
}
