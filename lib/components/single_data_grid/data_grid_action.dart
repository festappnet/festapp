import 'dart:async';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';

class DataGridAction {
  String? name;
  FutureOr<void> Function(SingleDataGridController,
      [Future<void> Function()? originalAction])? action;
  bool Function()? isEnabled;
  final bool requiresSelection;
  DataGridAction(
      {this.action, this.name, this.isEnabled, this.requiresSelection = false});
}

class DataGridActionsController {
  bool Function()? isAddActionPossible;
  bool Function()? areAllActionsEnabled;
  DataGridAction? saveAction;
  DataGridActionsController(
      {this.saveAction, this.areAllActionsEnabled, this.isAddActionPossible});
}
