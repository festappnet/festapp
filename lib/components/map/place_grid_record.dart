import 'package:festapp_core/map.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/map/map_commands.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:trina_grid/trina_grid.dart';

class PlaceGridRecord extends ITrinaRowModel {
  PlaceGridRecord(
      {required this.place, required this.commands, required this.occasionId});
  PlaceModel place;
  final MapCommands commands;
  final int occasionId;
  @override
  int? get id => place.id;
  @override
  String toBasicString() => place.toBasicString();
  @override
  TrinaRow toTrinaRow(BuildContext context) => toRow(place, context);
  static PlaceGridRecord fromPlutoJson(Map<String, dynamic> json,
          {required MapCommands commands, required int occasionId}) =>
      PlaceGridRecord(
          place: decode(json), commands: commands, occasionId: occasionId);
  static PlaceModel decode(Map<String, dynamic> json) {
    return PlaceModel(
        latLng: json[Tb.places.coordinates],
        id: json[Tb.places.id] == -1 ? null : json[Tb.places.id],
        aggregateVersion: TrinaRowVersion.read(json),
        title: json[Tb.places.title],
        description: json[Tb.places.description].isEmpty
            ? null
            : json[Tb.places.description],
        type: json[Tb.places.type] == PlaceModel.WithoutValue
            ? null
            : json[Tb.places.type],
        isHidden: json[Tb.places.is_hidden] == "true" ? true : false,
        order: json[Tb.places.order],
        icon: json[Tb.places.icon]);
  }

  static TrinaRow toRow(PlaceModel place, BuildContext context) {
    return TrinaRow(cells: {
      PlaceModel.aggregateVersionColumn:
          TrinaRowVersion.cell(place.aggregateVersion),
      Tb.places.id: TrinaCell(value: place.id),
      Tb.places.title: TrinaCell(value: place.title),
      Tb.places.description: TrinaCell(value: place.description ?? ""),
      Tb.places.coordinates: TrinaCell(value: place.latLng),
      Tb.places.type: TrinaCell(value: place.type ?? PlaceModel.WithoutValue),
      Tb.places.is_hidden: TrinaCell(value: place.isHidden.toString()),
      Tb.places.order: TrinaCell(value: place.order),
      Tb.places.icon: TrinaCell(value: place.icon),
    });
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    place = await DbPlaces.updatePlaceWithCommands(
        commands: commands, occasionId: occasionId, place: place);
  }

  @override
  Future<void> deleteMethod(BuildContext context) =>
      DbPlaces.deletePlaceWithCommands(
          commands: commands, occasionId: occasionId, place: place);
}

extension PlacePresentation on PlaceModel {
  String toPlutoSelectString() => '$id:$title';
}
