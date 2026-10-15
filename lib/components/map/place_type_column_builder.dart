import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:trina_grid/trina_grid.dart';

/// Builds the canonical editable `places.type` column.
///
/// The values stored on places are the stable [PlaceTypeModel.code] strings;
/// editors see the human-readable titles. Cleaning's built-in `toilet` code is
/// appended when needed, but never replaces occasion-defined place types.
TrinaColumn buildPlaceTypeColumn({
  required List<PlaceTypeModel> placeTypes,
  required bool includeToilet,
}) {
  final labels = <String, String>{};
  final codes = <String>[PlaceModel.WithoutValue];

  for (final placeType in placeTypes) {
    final code = placeType.code?.trim();
    if (code == null || code.isEmpty || labels.containsKey(code)) continue;
    codes.add(code);
    labels[code] = placeType.title?.trim().isNotEmpty == true
        ? placeType.title!.trim()
        : code;
  }

  if (includeToilet &&
      !labels.containsKey(CleaningStatusHelper.toiletPlaceTypeCode)) {
    codes.add(CleaningStatusHelper.toiletPlaceTypeCode);
    labels[CleaningStatusHelper.toiletPlaceTypeCode] =
        CleaningStrings.placeIsToilet;
  }

  String labelFor(dynamic value) {
    if (value == null || value == PlaceModel.WithoutValue) {
      return PlaceModel.WithoutValue;
    }
    return labels[value] ?? value.toString();
  }

  return TrinaColumn(
    title: CommonStrings.type,
    field: Tb.places.type,
    width: 180,
    applyFormatterInEditing: true,
    formatter: labelFor,
    type: TrinaColumnType.select<String>(
      codes,
      defaultValue: PlaceModel.WithoutValue,
      itemToString: labelFor,
      menuItemBuilder: (code) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(labelFor(code)),
        ),
      ),
    ),
  );
}
