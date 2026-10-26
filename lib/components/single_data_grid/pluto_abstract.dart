import 'package:material_ui/material_ui.dart';
import 'package:trina_grid/trina_grid.dart';

abstract class ITrinaRowModel {
  dynamic get id;

  TrinaRow toTrinaRow(BuildContext context);
  Future<void> deleteMethod(BuildContext context);
  Future<void> updateMethod(BuildContext context);
  String toBasicString();
}

/// Keeps an optimistic aggregate version alive while a model is represented
/// as an editable Trina row. The cell is intentionally not a visible column.
abstract final class TrinaRowVersion {
  static const String column = 'aggregate_version';

  static int read(Map<String, dynamic> json) =>
      (json[column] as num?)?.toInt() ?? 0;

  static TrinaCell cell(int version) => TrinaCell(value: version);
}
