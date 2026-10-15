import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  test('group editor bundle parses groups and existing places together', () {
    final groupTitle = GroupsStrings.newGroup;
    final placeTitle = GroupsStrings.choosePlace;
    final groupId = Tb.user_group_info.table.hashCode;
    final privatePlaceId = Tb.user_group_info.place.hashCode;
    final catalogPlaceId = Tb.places.table.hashCode;
    final data = DbGroups.parseUserGroupsEditorData({
      DbGroups.editorGroupsKey: [
        {
          Tb.user_group_info.id: groupId,
          Tb.user_group_info.title: groupTitle,
          Tb.user_group_info.place: privatePlaceId,
          Tb.places.table: {
            Tb.places.id: privatePlaceId,
            Tb.places.title: placeTitle,
            Tb.places.type: PlaceModel.groupType,
            Tb.places.is_hidden: true,
          },
          Tb.user_groups.table: [],
        }
      ],
      DbGroups.editorGameDefinitionsKey: null,
      DbGroups.editorPlacesKey: [
        {
          Tb.places.id: catalogPlaceId,
          Tb.places.title: placeTitle,
          Tb.places.type: PlaceModel.WithoutValue,
          Tb.places.is_hidden: false,
        }
      ],
    });

    expect(data.groups.single.id, groupId);
    expect(data.groups.single.title, groupTitle);
    expect(data.groups.single.persistedPlaceId, privatePlaceId);
    expect(data.groups.single.persistedPlaceWasPrivate, isTrue);
    expect(data.places.single.id, catalogPlaceId);
    expect(data.places.single.title, placeTitle);
    expect(data.places.single.isPrivateGroupLocation, isFalse);
  });
}
