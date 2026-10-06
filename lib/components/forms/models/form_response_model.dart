import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:trina_grid/trina_grid.dart';

import '../../eshop/db_orders.dart';

class FormResponseModel extends ITrinaRowModel {
  @override
  int? id;
  OrderModel? order;
  Map<String, dynamic>? fields;
  List<FormFieldModel>? allFields;

  FormResponseModel({
    this.id,
    this.order,
    this.fields,
    this.allFields,
  });

  static FormResponseModel fromPlutoJson(
      Map<String, dynamic> json, List<FormFieldModel> allFields) {
    final int? orderId = json[EshopColumns.ORDER_ID] as int?;
    final Map<String, dynamic> responseFields = {};

    // Create a quick lookup map for field models by their string ID
    final Map<String, FormFieldModel> fieldMap = {
      for (var f in allFields) f.id.toString(): f
    };

    for (var entry in json.entries) {
      final String fieldId = entry.key;
      final dynamic value = entry.value;

      // Find the corresponding field model using the ID (key)
      final FormFieldModel? fieldModel = fieldMap[fieldId];

      if (fieldModel != null) {
        // As requested, skip fields that are listed as non-editable
        // in FormHelper.nonEditableFields
        if (FormHelper.nonEditableFields.contains(fieldModel.type)) {
          continue; // Skip this field entirely
        }

        if (fieldModel.type == FormHelper.fieldTypeSex) {
          // Sex is independent, handled as a single string-to-string mapping
          responseFields[fieldId] =
              UserInfoModel.sexFromLocale(value as String?);
        } else if (fieldModel.type == FormHelper.fieldTypeBirthDate) {
          // BirthDate is handled
          final dt = DateTime.tryParse(value as String? ?? "");
          responseFields[fieldId] = dt?.toIso8601String();
        } else if (fieldModel.type == FormHelper.fieldTypeIdDocument) {
          // IdDocument is handled
          responseFields[fieldId] = value;
        } else if (fieldModel.type == FormHelper.fieldTypeSelectMany) {
          final String? stringValue = value as String?;
          if (stringValue == null || stringValue.isEmpty) {
            // If the grid value is empty, store an empty list
            responseFields[fieldId] = <String>[];
          } else {
            responseFields[fieldId] =
                stringValue.split(FormHelper.optionDelimiter);
          }
        } else {
          // Default for all other field types (text, number, etc.)
          responseFields[fieldId] = value;
        }
      } else if (int.tryParse(fieldId) != null) {
        // Preserve numeric keys even if not in allFields
        responseFields[fieldId] = value;
      }
    }

    return FormResponseModel(
      id: orderId,
      fields: responseFields,
      allFields: allFields,
    );
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    Map<String, TrinaCell> cells = {
      EshopColumns.ORDER_ID: TrinaCell(value: id),
      EshopColumns.ORDER_SYMBOL: TrinaCell(value: order!.toBasicString()),
      EshopColumns.ORDER_STATE:
          TrinaCell(value: OrderModel.formatState(order!.state!)),
      EshopColumns.TICKET_PRODUCTS: TrinaCell(
          value: order!.relatedProducts != null
              ? order!.relatedProducts!
                  .map((p) => p.toBasicString())
                  .join(" | ")
              : ""),
    };

    final productCells =
        EshopColumns.generateProductTypeCells(order!.relatedProducts ?? []);
    cells.addAll(productCells);

    // Process additional form fields.
    for (var f in allFields!) {
      if (fields == null) {
        cells[f.id.toString()] = TrinaCell(value: '');
        continue;
      }
      if (f.type == FormHelper.fieldTypeSex) {
        cells[f.id.toString()] = TrinaCell(
            value: UserInfoModel.sexToLocale(fields![f.id.toString()]));
        continue;
      } else if (f.type == FormHelper.fieldTypeIdDocument) {
        var val = fields![f.id.toString()];
        cells[f.id.toString()] = TrinaCell(value: val?.toString() ?? "");
        continue;
      } else if (f.type == FormHelper.fieldTypeBirthDate) {
        // Parse ISO datetime string into a DateTime object.
        var dt = DateTime.tryParse(fields![f.id.toString()] ?? "");
        // Format the DateTime into a "year-month-day" string.
        String formattedDate = dt == null
            ? ""
            : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        cells[f.id.toString()] = TrinaCell(value: formattedDate);
        continue;
      }
      var rValue = Utilities.removeTabsAndNewLines(
          (fields![f.id.toString()] ?? "").toString());
      cells[f.id.toString()] = TrinaCell(value: rValue);
    }

    return TrinaRow(cells: cells);
  }

  factory FormResponseModel.fromOrder(
      OrderModel order, List<FormFieldModel> allFields) {
    var fieldsData = order.data?[FormHelper.metaFields];

    Map<String, dynamic>? extractedFields;

    if (fieldsData != null && fieldsData is List) {
      // Transform the list of maps into a single map
      extractedFields = {
        for (var f in fieldsData)
          if (f is Map<String, dynamic>)
            for (var entry in f.entries) entry.key: entry.value,
      };
    } else {
      extractedFields = null;
    }

    return FormResponseModel(
        id: order.id,
        order: order,
        fields: extractedFields,
        allFields: allFields);
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {}

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbOrders.updateOrderResponses(this);
  }

  @override
  String toBasicString() {
    return order?.toBasicString() ?? "";
  }
}
