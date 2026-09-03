import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/icons/db_place_types.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/map/place_type_column_builder.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/map/map_page.dart';

import 'place_model.dart';

class PlacesContent extends StatefulWidget {
  const PlacesContent({super.key});

  @override
  _PlacesContentState createState() => _PlacesContentState();
}

class _PlacesContentState extends State<PlacesContent> {
  List<IconModel> svgIcons = [];
  List<int?> mapIcons = [];
  List<PlaceTypeModel> placeTypes = [];
  bool isLoading = true;
  SingleDataGridController<PlaceModel>? controller;

  @override
  void initState() {
    super.initState();
    loadOptions();
  }

  Future<void> loadOptions() async {
    try {
      final results = await Future.wait([
        DbPlaces.getAllIcons(),
        DbPlaceTypes.getPlaceTypes(),
      ]);
      final icons = results[0] as List<IconModel>;
      final loadedPlaceTypes = results[1] as List<PlaceTypeModel>;
      setState(() {
        svgIcons = icons;
        mapIcons = svgIcons.map((icon) => icon.id).toList();
        mapIcons.add(null); // "no icon" option
        placeTypes = loadedPlaceTypes;
        isLoading = false;
      });
      if (controller == null) initController();
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void initController() {
    controller ??= SingleDataGridController<PlaceModel>(
      context: context,
      loadData: DbPlaces.getAllPlacesForEditor,
      fromPlutoJson: PlaceModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.deleteAndDuplicate,
      idColumn: Tb.places.id,
      columns: [
        TrinaColumn(
          title: CommonStrings.id,
          field: Tb.places.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          width: 50,
          renderer: DataGridHelper.idRenderer,
        ),
        TrinaColumn(
          title: CommonStrings.hide,
          field: Tb.places.is_hidden,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 100,
          renderer: (ctx) =>
              DataGridHelper.checkBoxRenderer(ctx, Tb.places.is_hidden),
        ),
        TrinaColumn(
          title: CommonStrings.title,
          field: Tb.places.title,
          type: TrinaColumnType.text(),
          width: 300,
        ),
        TrinaColumn(
          title: CommonStrings.description,
          field: Tb.places.description,
          type: TrinaColumnType.text(),
          width: 150,
          renderer: (ctx) {
            return DataGridHelper.buildHtmlEditorButton(
              context: context,
              occasionId: RightsService.currentOccasionId(),
              field: Tb.places.description,
              title: ctx.row.cells[Tb.places.title]!.value,
              rendererContext: ctx,
              loadContent: () async =>
                  ctx.row.cells[Tb.places.description]!.value,
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.icon,
          field: Tb.places.icon,
          applyFormatterInEditing: true,
          formatter: (d) =>
              svgIcons.firstWhereOrNull((i) => i.id == d)?.displayLabel ??
              IconModel.missingLabel,
          type: TrinaColumnType.select(
            defaultValue: null,
            mapIcons,
            menuItemBuilder: (icon) =>
                DataGridHelper.iconToRow(context, icon, svgIcons),
          ),
          renderer: (ctx) =>
              DataGridHelper.mapIconRenderer(context, ctx, svgIcons),
        ),
        buildPlaceTypeColumn(
          placeTypes: placeTypes,
          includeToilet:
              FeatureService.isFeatureEnabled(FeatureConstants.cleaning),
        ),
        TrinaColumn(
          title: MapStrings.locationOnMap,
          field: Tb.places.coordinates,
          type: TrinaColumnType.text(
            defaultValue: FeatureService.getDefaultLocation(),
          ),
          width: 150,
          applyFormatterInEditing: true,
          enableEditingMode: false,
          enableFilterMenuItem: false,
          enableContextMenu: false,
          enableSorting: false,
          renderer: (ctx) {
            return ElevatedButton(
              onPressed: () async {
                var pm = PlaceModel.fromPlutoJson(ctx.row.toJson());
                var value = await RouterService.navigatePageInfo(
                  context,
                  MapEditorRoute(mode: PlaceMapEditorMode(pm)),
                );
                if (value != null) {
                  var cell = ctx.row.cells[Tb.places.coordinates]!;
                  ctx.stateManager
                      .changeCellValue(cell, value.toString(), force: true);
                  ctx.cell.value = value;
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.edit),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(CommonStrings.edit),
                  ),
                ],
              ),
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.order,
          field: Tb.places.order,
          type: TrinaColumnType.number(defaultValue: null),
          applyFormatterInEditing: true,
          width: 100,
        ),
      ],
    );

    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!isLoading && controller == null) initController();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<PlaceModel>(controller!);
  }
}
