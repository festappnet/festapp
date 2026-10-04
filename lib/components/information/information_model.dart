import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:trina_grid/trina_grid.dart';

class InformationModel extends ITrinaRowModel {
  static const String aggregateVersionColumn = TrinaRowVersion.column;
  static const String gameType = "game";
  static const String songType = "song";
  static const String quoteType = "quote";

  @override
  int? id;
  InformationHiddenModel? informationHidden;
  DateTime? updatedAt;
  String? title;
  String? description;
  String? type;
  bool? isHidden;
  int? order;
  int? unit;
  Map<String, dynamic>? data;
  int aggregateVersion;
  int getOrder() => order ?? 0;
  DateTime getDateTime() => data?[Tb.information.data_date] != null
      ? DateTime.parse(data?[Tb.information.data_date])
      : DateTime.fromMillisecondsSinceEpoch(0);

  bool isExpanded = false;

  static const String informationOffline = "information";

  factory InformationModel.fromJson(Map<String, dynamic> json) {
    return InformationModel(
        id: json[Tb.information.id],
        title: json[Tb.information.title],
        description: json[Tb.information.description],
        type: json[Tb.information.type],
        isHidden: json[Tb.information.is_hidden] ?? false,
        order: json[Tb.information.order] ?? 0,
        unit: json[Tb.information.unit],
        updatedAt: json[Tb.occasions.updated_at] != null
            ? DateTime.parse(json[Tb.occasions.updated_at])
            : null,
        data: json[Tb.information.data],
        aggregateVersion: TrinaRowVersion.read(json),
        informationHidden: json[Tb.information_hidden.table] != null
            ? InformationHiddenModel(
                id: json[Tb.information_hidden.table][Tb.information_hidden.id],
                data: json[Tb.information_hidden.table]
                    [Tb.information_hidden.data])
            : null);
  }

  factory InformationModel.newRow(int unitId) {
    return InformationModel(unit: unitId);
  }

  Map toJson() => {
        Tb.information.id: id,
        aggregateVersionColumn: aggregateVersion,
        Tb.information.title: title,
        Tb.information.description: description,
        Tb.information.type: type,
        Tb.information.is_hidden: isHidden,
        Tb.information.order: order,
        Tb.information.unit: unit,
        Tb.information.updated_at: updatedAt?.toIso8601String(),
        Tb.information.information_hidden: informationHidden,
        Tb.information.data: data
      };

  static InformationModel fromPlutoJson(Map<String, dynamic> json) {
    return InformationModel(
      id: json[Tb.information.id] == -1 ? null : json[Tb.information.id],
      aggregateVersion: TrinaRowVersion.read(json),
      title: json[Tb.information.title],
      description: json[Tb.information.description],
      type: json[Tb.information.type],
      isHidden: json[Tb.information.is_hidden] == "true" ? true : false,
      order: json[Tb.information.order],
      unit: json[Tb.information.unit],
    );
  }

  static InformationModel fromPlutoJsonGame(Map<String, dynamic> json) {
    return InformationModel(
        id: json[Tb.information.id] == -1 ? null : json[Tb.information.id],
        aggregateVersion: TrinaRowVersion.read(json),
        title: json[Tb.information.title],
        description: json[Tb.information.description],
        type: InformationModel.gameType,
        isHidden: json[Tb.information.is_hidden] == "true" ? true : false,
        order: json[Tb.information.order],
        unit: json[Tb.information.unit],
        informationHidden: json[Tb.information.data_correct] != null
            ? InformationHiddenModel(data: {
                Tb.information.data_correct: json[Tb.information.data_correct]
              }, id: json[Tb.information.data_correct_reference])
            : null);
  }

  static InformationModel fromPlutoJsonType(
      Map<String, dynamic> json, String type) {
    var quoteDate = type == quoteType && json[Tb.information.data_date] != null
        ? DateFormat("yyyy-MM-dd").parse(json[Tb.information.data_date])
        : null;
    return InformationModel(
      id: json[Tb.information.id] == -1 ? null : json[Tb.information.id],
      aggregateVersion: TrinaRowVersion.read(json),
      title: json[Tb.information.title],
      description: json[Tb.information.description],
      type: type,
      isHidden: json[Tb.information.is_hidden] == "true" ? true : false,
      order: json[Tb.information.order],
      unit: json[Tb.information.unit],
      data: quoteDate != null
          ? {Tb.information.data_date: quoteDate.toIso8601String()}
          : null,
    );
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    return TrinaRow(cells: {
      aggregateVersionColumn: TrinaRowVersion.cell(aggregateVersion),
      Tb.information.id: TrinaCell(value: id ?? -1),
      Tb.information.title: TrinaCell(value: title ?? ""),
      Tb.information.description: TrinaCell(value: description),
      Tb.information.type: TrinaCell(value: type ?? ""),
      Tb.information.is_hidden: TrinaCell(value: isHidden.toString()),
      Tb.information.order: TrinaCell(value: order),
      Tb.information.unit: TrinaCell(value: unit),
      Tb.information.data_correct: TrinaCell(
          value: informationHidden?.data?[Tb.information.data_correct] ?? ""),
      Tb.information.data_correct_reference:
          TrinaCell(value: informationHidden?.id),
      Tb.information.data_date: TrinaCell(
          value: data?[Tb.information.data_date] != null
              ? DateFormat('yyyy-MM-dd')
                  .format(DateTime.parse(data?[Tb.information.data_date]))
              : DateTime.now()),
    });
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbInformation.deleteInformation(this);
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbInformation.updateInformation(this);
  }

  @override
  String toBasicString() {
    if (data?[Tb.information.data_date] != null) {
      return DateFormat.yMMMd('en')
          .format(DateTime.parse(data?[Tb.information.data_date]))
          .toString();
    }
    return title ?? id.toString();
  }

  InformationModel(
      {this.id,
      this.updatedAt,
      this.title,
      this.description,
      this.type,
      this.isHidden,
      this.order,
      this.unit,
      this.informationHidden,
      this.data,
      this.aggregateVersion = 0});
}

class InformationHiddenModel {
  int? id;
  Map<String, dynamic>? data;

  InformationHiddenModel({this.id, this.data});
}
