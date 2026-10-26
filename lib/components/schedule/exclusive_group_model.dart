import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:trina_grid/trina_grid.dart';

class ExclusiveGroupModel extends ITrinaRowModel {
  static const String aggregateVersionColumn = TrinaRowVersion.column;
  @override
  int? id;
  String? title;
  List<int>? events;
  int aggregateVersion;

  ExclusiveGroupModel({
    required this.id,
    this.title,
    this.events,
    this.aggregateVersion = 0,
  });

  factory ExclusiveGroupModel.fromJson(Map<String, dynamic> json) {
    return ExclusiveGroupModel(
      id: json[Tb.exclusive_groups.id],
      title: json.containsKey(Tb.exclusive_groups.title)
          ? json[Tb.exclusive_groups.title]
          : null,
      events: json.containsKey(Tb.exclusive_events.table)
          ? List<int>.from(
              json[Tb.exclusive_events.table].map((e) => e["event"]))
          : null,
      aggregateVersion: TrinaRowVersion.read(json),
    );
  }

  static ExclusiveGroupModel fromPlutoJson(Map<String, dynamic> json) {
    List<int> events = [];
    if (json[Tb.events.table].toString().trim().isNotEmpty) {
      events = json[Tb.events.table]
          .toString()
          .split(",")
          .map((e) => int.parse(e.trim()))
          .toList();
    }

    return ExclusiveGroupModel(
        id: json[Tb.exclusive_groups.id] == -1
            ? null
            : json[Tb.exclusive_groups.id],
        aggregateVersion: TrinaRowVersion.read(json),
        title: json[Tb.exclusive_groups.title],
        events: events);
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    return TrinaRow(cells: {
      aggregateVersionColumn: TrinaRowVersion.cell(aggregateVersion),
      Tb.exclusive_groups.id: TrinaCell(value: id),
      Tb.exclusive_groups.title: TrinaCell(value: title),
      Tb.events.table:
          TrinaCell(value: events?.map((e) => e.toString()).join(",") ?? "")
    });
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbEvents.deleteExclusiveGroup(this);
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbEvents.updateExclusiveGroup(this);
  }

  @override
  String toBasicString() => "$title";
}
