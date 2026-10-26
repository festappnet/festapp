import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class InformationContent extends StatefulWidget {
  const InformationContent({super.key});

  @override
  _InformationContentState createState() => _InformationContentState();
}

class _InformationContentState extends State<InformationContent> {
  SingleDataGridController<InformationModel>? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller ??= SingleDataGridController<InformationModel>(
      context: context,
      loadData: DbInformation.getAllInformationForDataGrid,
      fromPlutoJson: InformationModel.fromPlutoJson,
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
              context: context,
              occasionId: RightsService.currentOccasionId(),
              field: Tb.information.description,
              rendererContext: rendererContext,
              title: rendererContext.row.cells[Tb.information.title]!.value,
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
        TrinaColumn(
          title: CommonStrings.type,
          field: Tb.information.type,
          type: TrinaColumnType.text(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleTableDataGrid<InformationModel>(controller!);
  }
}
