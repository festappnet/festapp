import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';

class UnitUserModel extends ITrinaRowModel {
  int? unit;
  String? user;
  String? name;
  String? surname;
  String? sex;
  String? emailReadonly;
  bool? isManager;
  bool? isEditor;
  bool? isEditorView;
  Map<String, dynamic>? data;

  UnitUserModel({
    this.unit,
    this.user,
    this.name,
    this.surname,
    this.sex,
    this.emailReadonly,
    this.isManager,
    this.isEditor,
    this.isEditorView,
    this.data,
  });

  factory UnitUserModel.fromJson(Map<String, dynamic> json) {
    return UnitUserModel(
      unit: json[Tb.unit_users.unit],
      user: json[Tb.occasion_users.user],
      name: json[Tb.occasion_users.data_name]?.toString().trim(),
      surname: json[Tb.occasion_users.data_surname]?.toString().trim(),
      sex: json[Tb.occasion_users.data_sex]?.toString().trim(),
      emailReadonly: json[Tb.user_info.email_readonly]?.toString().trim(),
      isManager: json[Tb.occasion_users.is_manager] == true ||
          json[Tb.occasion_users.is_manager]?.toString().toLowerCase() ==
              'true',
      isEditor: json[Tb.occasion_users.is_editor] == true ||
          json[Tb.occasion_users.is_editor]?.toString().toLowerCase() == 'true',
      isEditorView: json[Tb.occasion_users.is_editor_view] == true ||
          json[Tb.occasion_users.is_editor_view]?.toString().toLowerCase() ==
              'true',
      data: json[Tb.occasion_users.data] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json[Tb.occasion_users.data])
          : {},
    );
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    final Map<String, TrinaCell> cells = {
      UserColumns.ID: TrinaCell(value: user),
      UserColumns.UNIT: TrinaCell(value: unit),
      UserColumns.NAME: TrinaCell(value: name ?? ""),
      UserColumns.SURNAME: TrinaCell(value: surname ?? ""),
      UserColumns.SEX: TrinaCell(value: sex ?? ""),
      UserColumns.EMAIL: TrinaCell(value: emailReadonly ?? ""),
      UserColumns.UNIT_MANAGER: TrinaCell(value: isManager.toString()),
      UserColumns.UNIT_EDITOR: TrinaCell(value: isEditor.toString()),
      UserColumns.UNIT_EDITOR_VIEW: TrinaCell(value: isEditorView.toString()),
    };

    return TrinaRow(cells: cells);
  }

  factory UnitUserModel.newRow(int unitId) {
    return UnitUserModel(unit: unitId);
  }

  static UnitUserModel fromPlutoJson(Map<String, dynamic> json) {
    return UnitUserModel(
        unit: json[UserColumns.UNIT],
        user: json[UserColumns.ID],
        name: json[UserColumns.NAME],
        surname: json[UserColumns.SURNAME],
        sex: json[UserColumns.SEX],
        emailReadonly: json[UserColumns.EMAIL],
        isManager: json[UserColumns.UNIT_MANAGER] == "true" ? true : false,
        isEditor: json[UserColumns.UNIT_EDITOR] == "true" ? true : false,
        isEditorView:
            json[UserColumns.UNIT_EDITOR_VIEW] == "true" ? true : false,
        // The 'data' field is not represented in UserColumns or created in toTrinaRow.
        // It is omitted here as it cannot be mapped from the grid data.
        data: json[Tb.occasion_users.data]);
  }

  Map toJson() => {
        Tb.unit_users.user: user,
        Tb.unit_users.unit: unit,
        Tb.user_info.name: name,
        Tb.user_info.surname: surname,
        Tb.user_info.sex: sex,
        Tb.occasion_users.data_email: emailReadonly,
        Tb.unit_users.is_manager: isManager,
        Tb.unit_users.is_editor: isEditor,
        Tb.unit_users.is_editor_view: isEditorView,
        Tb.unit_users.data: data,
      };

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbUsers.deleteUnitUser(user!, unit!);
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbUsers.updateUnitUser(this);
  }

  @override
  String toBasicString() => emailReadonly ?? "";

  @override
  get id => user;
}
