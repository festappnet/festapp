import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class GameCheckPointsContent extends StatefulWidget {
  const GameCheckPointsContent({super.key});

  @override
  _GameCheckPointsContentState createState() => _GameCheckPointsContentState();
}

class _GameCheckPointsContentState extends State<GameCheckPointsContent> {
  SingleDataGridController<InformationModel>? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller ??= SingleDataGridController<InformationModel>(
      context: context,
      loadData: () =>
          DbInformation.getAllInformationForDataGrid(InformationModel.gameType),
      fromPlutoJson: InformationModel.fromPlutoJsonGame,
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
          title: CommonStrings.title,
          enableAutoEditing: true,
          field: Tb.information.title,
          type: TrinaColumnType.text(),
        ),
        TrinaColumn(
          enableAutoEditing: true,
          title: GroupsStrings.correctAnswer,
          field: Tb.information.data_correct,
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
