import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class SongbookContent extends StatefulWidget {
  const SongbookContent({super.key});

  @override
  _SongbookContentState createState() => _SongbookContentState();
}

class _SongbookContentState extends State<SongbookContent> {
  SingleDataGridController<InformationModel>? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller ??= SingleDataGridController<InformationModel>(
      context: context,
      loadData: () =>
          DbInformation.getAllInformationForDataGrid(InformationModel.songType),
      fromPlutoJson: (plutoData) => InformationModel.fromPlutoJsonType(
          plutoData, InformationModel.songType),
      firstColumnType: DataGridFirstColumn.deleteAndDuplicate,
      idColumn: Tb.information.id,
      columns: [
        TrinaColumn(
          hide: true,
          title: CommonStrings.id,
          field: Tb.information.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          width: 50,
          renderer: (rendererContext) =>
              DataGridHelper.idRenderer(rendererContext),
        ),
        TrinaColumn(
          title: CommonStrings.hide,
          field: Tb.information.is_hidden,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 100,
          renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext, Tb.information.is_hidden),
        ),
        TrinaColumn(
          title: CommonStrings.title,
          field: Tb.information.title,
          type: TrinaColumnType.text(),
        ),
        TrinaColumn(
          width: 150,
          title: CommonStrings.content,
          field: Tb.information.description,
          type: TrinaColumnType.text(),
          renderer: (rendererContext) {
            return DataGridHelper.buildHtmlEditorButton(
                profile: HtmlContentProfile.songContent,
              context: context,
              occasionId: RightsService.currentOccasionId(),
              field: Tb.information.description,
              title: rendererContext.row.cells[Tb.information.title]!.value,
              rendererContext: rendererContext,
              loadContent: () async {
                return rendererContext
                    .row.cells[Tb.information.description]!.value;
              },
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.order,
          field: Tb.information.order,
          type: TrinaColumnType.number(defaultValue: null),
          applyFormatterInEditing: true,
          width: 100,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleTableDataGrid<InformationModel>(controller!);
  }
}
