import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/icons/db_place_types.dart';
import 'package:fstapp/components/icons/icons_strings.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:trina_grid/trina_grid.dart';

/// "Place types" data grid — the 3rd subtab under the Places admin tab.
/// Mirrors the deployed columns: Id, Hide, Default, Code, Title, Icon, Order.
class PlaceTypesContent extends StatefulWidget {
  const PlaceTypesContent({super.key});

  @override
  State<PlaceTypesContent> createState() => _PlaceTypesContentState();
}

class _PlaceTypesContentState extends State<PlaceTypesContent> {
  SingleDataGridController<PlaceTypeModel>? controller;
  bool isLoading = true;
  List<IconModel> svgIcons = [];
  List<int?> mapIcons = [];

  @override
  void initState() {
    super.initState();
    _loadIcons();
  }

  Future<void> _loadIcons() async {
    try {
      final icons = await DbPlaces.getAllIcons();
      setState(() {
        svgIcons = icons;
        mapIcons = svgIcons.map((icon) => icon.id).toList()..add(null);
        isLoading = false;
      });
      _initController();
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void _initController() {
    if (controller != null || isLoading) return;

    controller = SingleDataGridController<PlaceTypeModel>(
      context: context,
      loadData: DbPlaceTypes.getPlaceTypes,
      fromPlutoJson: PlaceTypeModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.deleteAndDuplicate,
      idColumn: Tb.place_types.id,
      columns: [
        TrinaColumn(
          hide: true,
          title: CommonStrings.id,
          field: Tb.place_types.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          width: 50,
          renderer: DataGridHelper.idRenderer,
        ),
        TrinaColumn(
          title: CommonStrings.hide,
          field: Tb.place_types.is_hidden,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 90,
          renderer: (ctx) =>
              DataGridHelper.checkBoxRenderer(ctx, Tb.place_types.is_hidden),
        ),
        TrinaColumn(
          title: IconsStrings.placeTypeDefault,
          field: Tb.place_types.is_default,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 100,
          renderer: (ctx) =>
              DataGridHelper.checkBoxRenderer(ctx, Tb.place_types.is_default),
        ),
        TrinaColumn(
          title: IconsStrings.placeTypeCode,
          field: Tb.place_types.code,
          type: TrinaColumnType.text(),
          width: 180,
        ),
        TrinaColumn(
          title: IconsStrings.placeTypeTitle,
          field: Tb.place_types.title,
          type: TrinaColumnType.text(),
          width: 280,
        ),
        TrinaColumn(
          title: CommonStrings.icon,
          field: Tb.place_types.icon,
          applyFormatterInEditing: true,
          formatter: (d) =>
              svgIcons.firstWhereOrNull((i) => i.id == d)?.displayLabel ??
              IconModel.missingLabel,
          type: TrinaColumnType.select(
            mapIcons,
            menuItemBuilder: (icon) =>
                DataGridHelper.iconToRow(context, icon, svgIcons),
            defaultValue: null,
          ),
          renderer: (ctx) =>
              DataGridHelper.mapIconRenderer(context, ctx, svgIcons),
        ),
        TrinaColumn(
          title: CommonStrings.order,
          field: Tb.place_types.order,
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
    _initController();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<PlaceTypeModel>(controller!);
  }
}
