import 'package:fstapp/components/map/place_grid_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  testWidgets('map admin grids preserve optimistic versions', (tester) async {
    const expectedAggregateVersion = 11;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const SizedBox();
      }),
    ));

    final place = PlaceModel.fromJson({
      Tb.places.id: 1,
      Tb.places.title: 'Stage',
      Tb.places.description: '',
      Tb.places.coordinates: <String, dynamic>{
        PlaceModel.coordinatesLatLngKey: <String, dynamic>{
          PlaceModel.latitudeKey: 49.1,
          PlaceModel.longitudeKey: 18.2,
        },
      },
      TrinaRowVersion.column: expectedAggregateVersion,
    });
    final placeType = PlaceTypeModel.fromJson({
      Tb.place_types.id: 2,
      Tb.place_types.code: 'stage',
      Tb.place_types.title: 'Stage',
      TrinaRowVersion.column: expectedAggregateVersion,
    });
    final path = PathGroupsModel.fromJson({
      Tb.path_groups.id: 3,
      Tb.path_groups.title: 'Main route',
      Tb.path_groups.path_data: <dynamic>[],
      TrinaRowVersion.column: expectedAggregateVersion,
    });

    expect(
      PlaceGridRecord.decode(PlaceGridRecord.toRow(place, context).toJson())
          .aggregateVersion,
      expectedAggregateVersion,
    );
    expect(
      PlaceTypeModel.fromPlutoJson(placeType.toTrinaRow(context).toJson())
          .aggregateVersion,
      expectedAggregateVersion,
    );
    expect(
      PathGroupsModel.fromPlutoJson(path.toTrinaRow(context).toJson())
          .aggregateVersion,
      expectedAggregateVersion,
    );
  });
}
