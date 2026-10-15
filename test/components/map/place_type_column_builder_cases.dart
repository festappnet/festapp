import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/map/place_type_column_builder.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:trina_grid/trina_grid.dart';

void main() {
  test('places grid always exposes every configured place type', () {
    final column = buildPlaceTypeColumn(
      placeTypes: [
        PlaceTypeModel(code: 'stage', title: 'Stage'),
        PlaceTypeModel(code: 'food', title: 'Food'),
      ],
      includeToilet: false,
    );

    expect(column.field, Tb.places.type);
    final type = column.type as TrinaColumnTypeSelect<String>;
    expect(
      type.items,
      [PlaceModel.WithoutValue, 'stage', 'food'],
    );
    expect(column.formatter?.call('stage'), 'Stage');
  });

  test('cleaning adds toilet without replacing configured types', () {
    final column = buildPlaceTypeColumn(
      placeTypes: [PlaceTypeModel(code: 'stage', title: 'Stage')],
      includeToilet: true,
    );

    final type = column.type as TrinaColumnTypeSelect<String>;
    expect(type.items, [PlaceModel.WithoutValue, 'stage', 'toilet']);
    expect(type.items.toSet().length, type.items.length);
  });
}
