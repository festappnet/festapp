import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:trina_grid/trina_grid.dart';

import '../../_shared/common_strings.dart';

class QuotesTab extends StatelessWidget {
  final int unitId;

  const QuotesTab({super.key, required this.unitId});

  @override
  Widget build(BuildContext context) {
    return SingleTableDataGrid<InformationModel>(
      SingleDataGridController<InformationModel>(
        context: context,
        loadData: () => DbInformation.getAllInformationForDataGridForUnit(
            unitId, InformationModel.quoteType),
        fromPlutoJson: (plutoData) => InformationModel.fromPlutoJsonType(
            plutoData, InformationModel.quoteType),
        firstColumnType: DataGridFirstColumn.delete,
        idColumn: Tb.information.id,
        getNewObject: () => InformationModel.newRow(unitId),
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
            hide: true,
            title: UnitStrings.unit,
            field: Tb.information.unit,
            type: TrinaColumnType.number(
                defaultValue: RightsService.currentUnit()!.id!),
            readOnly: true,
            width: 50,
          ),
          TrinaColumn(
            title: CommonStrings.date,
            enableAutoEditing: true,
            field: Tb.information.data_date,
            type: TrinaColumnType.date(),
            width: 300,
          ),
          TrinaColumn(
            width: 150,
            title: CommonStrings.content,
            field: Tb.information.description,
            type: TrinaColumnType.text(),
            renderer: (rendererContext) {
              return DataGridHelper.buildHtmlEditorButton(
                context: context,
                field: Tb.information.description,
                unitId: unitId,
                title: rendererContext.row.cells[Tb.information.title]!.value,
                rendererContext: rendererContext,
                loadContent: () async {
                  return rendererContext
                      .row.cells[Tb.information.description]!.value;
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
