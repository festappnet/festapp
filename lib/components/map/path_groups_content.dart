import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/map_page.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:trina_grid/trina_grid.dart';

class PathGroupsContent extends StatefulWidget {
  const PathGroupsContent({super.key});

  @override
  _PathGroupsContentState createState() => _PathGroupsContentState();
}

class _PathGroupsContentState extends State<PathGroupsContent> {
  SingleDataGridController<PathGroupsModel>? controller;
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
        mapIcons = svgIcons.map((icon) => icon.id).toList()
          ..add(null); // allow “no icon”
        isLoading = false;
      });
      _initController();
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void _initController() {
    if (controller != null || isLoading) return;

    controller = SingleDataGridController<PathGroupsModel>(
      context: context,
      loadData: DbPlaces.getAllPathGroups,
      fromPlutoJson: PathGroupsModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.deleteAndDuplicate,
      idColumn: Tb.path_groups.id,
      columns: [
        TrinaColumn(
          hide: true,
          title: CommonStrings.id,
          field: Tb.path_groups.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          width: 50,
          renderer: DataGridHelper.idRenderer,
        ),
        TrinaColumn(
          title: CommonStrings.hide,
          field: Tb.path_groups.is_hidden,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 100,
          renderer: (ctx) =>
              DataGridHelper.checkBoxRenderer(ctx, Tb.path_groups.is_hidden),
        ),
        TrinaColumn(
          title: CommonStrings.name,
          field: Tb.path_groups.title,
          type: TrinaColumnType.text(),
          width: 300,
        ),
        TrinaColumn(
          title: CommonStrings.color,
          field: Tb.path_groups.color,
          type: TrinaColumnType.text(defaultValue: ""),
          width: 120,
          enableEditingMode: false,
          renderer: (ctx) {
            final hex = (ctx.cell.value as String?) ?? "";
            Color? col = _parseHexColor(hex);
            return InkWell(
              onTap: () => _pickColor(ctx),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: col ?? Colors.transparent,
                      border: Border.all(color: Colors.black26),
                    ),
                    child: col == null
                        ? const Icon(Icons.add, size: 16, color: Colors.black38)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      col == null ? "" : hex.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.icon,
          field: Tb.path_groups.icon,
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
          title: CommonStrings.edit,
          field: Tb.path_groups.path_data,
          type: TrinaColumnType.text(),
          width: 150,
          enableEditingMode: false,
          enableFilterMenuItem: false,
          enableContextMenu: false,
          enableSorting: false,
          renderer: (ctx) {
            return ElevatedButton.icon(
              onPressed: () async {
                final pm = PathGroupsModel.fromPlutoJson(ctx.row.toJson());
                final value = await RouterService.navigatePageInfo(
                  context,
                  MapEditorRoute(mode: PathMapEditorMode(pm)),
                );
                if (value != null) {
                  final cell = ctx.row.cells[Tb.places.table]!;
                  ctx.stateManager
                      .changeCellValue(cell, value.toString(), force: true);
                }
              },
              icon: const Icon(Icons.edit_location_alt),
              label: Text(CommonStrings.edit),
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.places,
          field: Tb.places.table,
          type: TrinaColumnType.text(),
          width: 500,
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

  /// Parse a stored "#AARRGGBB" (or "#RRGGBB") hex string into a Color.
  /// Returns null when empty/invalid so the swatch can show an "empty" state.
  Color? _parseHexColor(String hex) {
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.isEmpty) return null;
    try {
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// "#AARRGGBB" — the format the map renderer expects (alpha first).
  String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  /// Open a color picker for the tapped cell and write the result back.
  void _pickColor(TrinaColumnRendererContext ctx) {
    final current =
        _parseHexColor((ctx.cell.value as String?) ?? "") ?? Colors.blue;
    showDialog(
      context: context,
      builder: (dialogContext) {
        Color pickerColor = current;
        // Shown without the leading '#'; the prefix icon already renders one.
        final hexController = TextEditingController(
            text: _colorToHex(pickerColor).replaceFirst('#', ''));
        final hexFocus = FocusNode();
        return AlertDialog(
          title: Text(CommonStrings.color),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Full picker first: the clickable saturation/value area
                      // plus the hue (tone) slider row underneath it.
                      ColorPicker(
                        pickerColor: pickerColor,
                        enableAlpha: false,
                        labelTypes: const [],
                        portraitOnly: true,
                        pickerAreaHeightPercent: 0.8,
                        onColorChanged: (c) {
                          setDialogState(() {
                            pickerColor = c;
                            if (!hexFocus.hasFocus) {
                              hexController.text =
                                  _colorToHex(c).replaceFirst('#', '');
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Hex kept below the picker so it reads as the exact value.
                      TextField(
                        controller: hexController,
                        focusNode: hexFocus,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: CommonStrings.hex,
                          hintText: CommonStrings.hexFormat,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.tag),
                        ),
                        onChanged: (val) {
                          final c = _parseHexColor(val);
                          if (c != null) {
                            setDialogState(() => pickerColor = c);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(CommonStrings.storno),
            ),
            ElevatedButton(
              onPressed: () {
                ctx.stateManager.changeCellValue(
                  ctx.cell,
                  _colorToHex(pickerColor),
                  force: true,
                );
                Navigator.of(dialogContext).pop();
              },
              child: Text(CommonStrings.ok),
            ),
          ],
        );
      },
    );
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
    return SingleTableDataGrid<PathGroupsModel>(controller!);
  }
}
