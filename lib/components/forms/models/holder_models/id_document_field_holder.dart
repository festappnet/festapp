import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:material_ui/material_ui.dart';
import 'id_document_data.dart';

class IdDocumentFieldHolder extends FieldHolder {
  // Metadata keys, defined within this model class
  static const String metaShowExpiryDate = "show_expiry_date";
  static const String metaExpiryDateLabel = "expiry_date_label";

  final bool showExpiryDate;
  final String? expiryDateLabel;

  IdDocumentFieldHolder({
    required super.id,
    required super.fieldType,
    required super.isRequired,
    super.title,
    super.description,
    this.showExpiryDate = false,
    this.expiryDateLabel,
  });

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()
      ..addAll({
        metaShowExpiryDate: showExpiryDate,
        metaExpiryDateLabel: expiryDateLabel,
      });
  }

  IdDocumentData? getIdDocumentData(GlobalKey<FormBuilderState> formKey) {
    final String idNumberFieldName = id.toString();
    final String expiryDateFieldName = "${id}_expiry";

    final idNumberValue =
        formKey.currentState?.fields[idNumberFieldName]?.value as String?;

    if (idNumberValue == null || idNumberValue.trim().isEmpty) {
      return null;
    }

    DateTime? expiryDateValue;
    if (showExpiryDate) {
      expiryDateValue =
          formKey.currentState?.fields[expiryDateFieldName]?.value as DateTime?;
    }

    return IdDocumentData(
      idNumber: idNumberValue.trim(),
      expiryDate: expiryDateValue,
    );
  }

  @override
  String toString() =>
      'IdDocumentFieldHolder(fieldType: $fieldType, title: $title, showExpiryDate: $showExpiryDate, expiryDateLabel: $expiryDateLabel, isRequired: $isRequired)';
}
