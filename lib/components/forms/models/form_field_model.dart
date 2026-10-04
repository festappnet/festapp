import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:intl/intl.dart';
import 'package:trina_grid/trina_grid.dart';

class FormFieldModel extends ITrinaRowModel {
  @override
  int? id;
  String? deleteBlockedReason;
  bool? deletionAllowed;
  bool get canDelete => id == null || deletionAllowed == true;
  DateTime? createdAt;
  DateTime? updatedAt;
  String? title;
  String? description;
  String? type;
  bool? isRequired;
  bool? isHidden;
  bool? isTicketField;
  int? form;
  int? order;
  int? productTypeId;
  dynamic data;
  List<FormOptionModel> options;
  ProductTypeModel? productType;

  static const String metaRequired = "required";
  static const String metaHidden = "hidden";
  static const String metaTitle = "title";
  static const String metaDescription = "description";

  FormFieldModel({
    this.id,
    this.deleteBlockedReason,
    this.deletionAllowed,
    this.createdAt,
    this.updatedAt,
    this.title,
    this.description,
    this.type,
    this.isRequired,
    this.isHidden,
    this.isTicketField,
    this.form,
    this.order,
    this.data,
    this.productTypeId,
    this.productType,
    List<FormOptionModel>? options,
  }) : options = options ?? [];

  factory FormFieldModel.fromJson(Map<String, dynamic> json) {
    var type = json[Tb.form_fields.type];
    var data = json[Tb.form_fields.data];
    List<FormOptionModel> options = [];
    if ((type == FormHelper.fieldTypeSelectOne ||
            type == FormHelper.fieldTypeSelectMany) &&
        data is Map) {
      options = data[FormHelper.metaOptions].map<FormOptionModel>((e) {
        return FormOptionModel.fromJson(e);
      }).toList();
    }
    return FormFieldModel(
        id: json[Tb.form_fields.id],
        deleteBlockedReason: json['delete_blocked_reason'],
        deletionAllowed: json['can_delete'],
        createdAt: json[Tb.form_fields.created_at] != null
            ? DateTime.parse(json[Tb.form_fields.created_at])
            : null,
        title: json[Tb.form_fields.title],
        description: json[Tb.form_fields.description],
        type: type,
        isRequired: json[Tb.form_fields.is_required],
        isHidden: json[Tb.form_fields.is_hidden],
        isTicketField: json[Tb.form_fields.is_ticket_field],
        form: json[Tb.form_fields.form],
        order: json[Tb.form_fields.order],
        data: data,
        productTypeId: json[Tb.form_fields.product_type],
        productType: json[Tb.form_fields.product_type_data] != null
            ? ProductTypeModel.fromJson(json[Tb.form_fields.product_type_data])
            : null,
        options: options);
  }

  Map<String, dynamic> toJson() {
    final jsonData = Map<String, dynamic>.from(data ?? {});

    if (options.isNotEmpty) {
      jsonData[FormHelper.metaOptions] = options.map((option) {
        final optionData = {FormOptionModel.metaValue: option.title};
        if (option.description != null &&
            option.description!.trim().isNotEmpty) {
          optionData[FormOptionModel.metaDescription] = option.description!;
        }
        return optionData;
      }).toList();
    }

    return {
      Tb.form_fields.id: id,
      Tb.form_fields.title: title,
      Tb.form_fields.description: description,
      Tb.form_fields.type: type,
      Tb.form_fields.is_required: isRequired,
      Tb.form_fields.is_hidden: isHidden,
      Tb.form_fields.is_ticket_field: isTicketField,
      Tb.form_fields.order: order,
      Tb.form_fields.data: jsonData.isNotEmpty ? jsonData : null,
      Tb.form_fields.product_type: productType,
    };
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    return TrinaRow(cells: {
      Tb.form_fields.id: TrinaCell(value: id ?? 0),
      Tb.form_fields.created_at: TrinaCell(
          value: createdAt != null
              ? DateFormat('yyyy-MM-dd').format(createdAt!)
              : ""),
      Tb.form_fields.title: TrinaCell(value: title ?? ""),
      Tb.form_fields.description: TrinaCell(value: description ?? ""),
      Tb.form_fields.type: TrinaCell(value: type ?? ""),
      metaRequired: TrinaCell(value: isRequired.toString()),
      metaHidden: TrinaCell(value: isHidden.toString()),
      Tb.form_fields.is_ticket_field:
          TrinaCell(value: isTicketField.toString()),
      Tb.form_fields.order: TrinaCell(value: order ?? 0),
    });
  }

  static FormFieldModel fromPlutoJson(Map<String, dynamic> json) {
    return FormFieldModel(
      id: json[Tb.form_fields.id] == -1 ? null : json[Tb.form_fields.id],
      isHidden: json[Tb.form_fields.is_hidden],
      isTicketField: json[Tb.form_fields.is_ticket_field],
    );
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {}

  @override
  Future<void> updateMethod(BuildContext context) async {}

  @override
  String toBasicString() => title ?? id.toString();
}
