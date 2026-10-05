import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/forms/models/form_option_product_model.dart';
import 'field_holder.dart';
import 'id_document_field_holder.dart';
import 'birth_date_field_holder.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/_shared/person_fields_strings.dart';

import 'ticket_holder.dart';

class FormHolderController {
  final String? secret;
  final int? blueprintId;
  final GlobalKey<FormBuilderState> globalKey;
  final String? formKey;
  String? currencyCode;
  void Function()? updateTotalPrice;
  Future<List<BlueprintSeat>?> Function(List<BlueprintSeat>)?
      showSeatReservation;
  void Function(List<BlueprintSeat>?)? onCloseSeatReservation;

  FormHolderController({
    this.secret,
    this.blueprintId,
    required this.globalKey,
    this.formKey,
    this.updateTotalPrice,
    this.showSeatReservation,
    this.onCloseSeatReservation,
  });
}

class FormHolder {
  static const String metaFields = "fields";

  FormHolderController? controller;
  final List<FieldHolder> fields;
  final bool isCardDesign;
  final List<String> phonePrefixes;
  final String? communicationTone;
  String? paymentType;

  TicketHolder? getTicket() =>
      fields.firstWhereOrNull((f) => f is TicketHolder) as TicketHolder?;

  FormHolder(
      {required this.fields,
      required this.isCardDesign,
      this.phonePrefixes = const [],
      this.communicationTone});

  factory FormHolder.fromFormFieldModel(FormModel formModel) {
    // Extract and sort ticket child fields.
    final ticketChildFields = formModel.relatedFields
        .where((f) =>
            f.isTicketField == true &&
            !(f.type == FormHelper.fieldTypeSpot && f.isHidden == true) &&
            !(f.type == FormHelper.fieldTypeProductType &&
                f.productType?.type == ProductModel.spotType &&
                formModel.usesSeatSelection))
        .toList()
      ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));

    // Process non-ticket fields.
    final otherFields = formModel.relatedFields
        .where((f) =>
            f.isTicketField != true &&
            !(f.type == FormHelper.fieldTypeProductType &&
                f.productType?.type == ProductModel.spotType &&
                formModel.usesSeatSelection))
        .map((f) => createFieldHolder(f))
        .toList();

    // Find the ticket field, if any.
    TicketHolder? ticket = otherFields.firstWhereOrNull(
        (f) => f.fieldType == FormHelper.fieldTypeTicket) as TicketHolder?;
    if (ticket != null) {
      ticket.fields.addAll(ticketChildFields.map((f) => createFieldHolder(f)));
    }
    return FormHolder(
        fields: otherFields,
        isCardDesign: formModel.isCardDesign,
        phonePrefixes:
            formModel.data != null && formModel.data!['phone_prefixes'] != null
                ? List<String>.from(formModel.data!['phone_prefixes'])
                : [],
        communicationTone: formModel.communicationTone);
  }

  /// Creates a [FieldHolder] instance based on the provided [FormFieldModel].
  static FieldHolder createFieldHolder(FormFieldModel ffm) {
    final fieldType = ffm.type;
    if (fieldType == FormHelper.fieldTypeTicket) {
      return TicketHolder(
        id: ffm.id!,
        fieldType: ffm.type!,
        maxTickets:
            ffm.data != null ? ffm.data[FormHelper.metaMaxTickets] ?? 1 : 1,
        showDepositDescription: ffm.data != null
            ? ffm.data[TicketHolder.metaShowDepositDescription] ?? true
            : true,
        fields: [],
        isRequired: true,
      );
    } else if (fieldType == FormHelper.fieldTypeSelectOne ||
        fieldType == FormHelper.fieldTypeSelectMany) {
      // Safely extract the options list from ffm.data.
      List<dynamic> optionsData = ffm.data[FormHelper.metaOptions] ?? [];

      // Convert each option to a FormOptionModel.
      List<FormOptionModel> formOptions = optionsData.mapIndexed((index, o) {
        String value = '';
        if (o is Map<String, dynamic> &&
            o.containsKey(FormOptionModel.metaValue)) {
          value = o[FormOptionModel.metaValue]?.toString() ?? '';
        }
        String description = '';
        if (o is Map<String, dynamic> &&
            o.containsKey(FormOptionModel.metaDescription)) {
          description = o[FormOptionModel.metaDescription]?.toString() ?? '';
        }
        return FormOptionModel(index.toString(), value,
            description: description);
      }).toList();

      return OptionsFieldHolder(
          id: ffm.id!,
          fieldType: ffm.type!,
          isRequired: ffm.isRequired ?? false,
          options: formOptions,
          value: ffm.data is Map
              ? (ffm.data as Map)[FormHelper.metaDefaultValue]
              : null,
          title: ffm.title ?? "",
          description: ffm.description);
    } else if (fieldType == FormHelper.fieldTypeProductType) {
      final selType = ffm.data?[FormHelper.metaSelectionType]?.toString();
      final prodSelectionType =
          (selType != null && selType == FormHelper.metaSelectionTypeMany)
              ? OptionsFieldProductSelectionType.selectMany
              : OptionsFieldProductSelectionType.selectOne;
      return OptionsFieldProductHolder(
          id: ffm.id!,
          fieldType: ffm.type!,
          selectionType: prodSelectionType,
          isRequired: ffm.isRequired ?? false,
          value: ffm.data is Map
              ? (ffm.data as Map)[FormHelper.metaDefaultValue]
              : null,
          productOptions: ffm.productType!.products!
              .map((p) => FormOptionProductModel(
                    p.id.toString(),
                    p.title!,
                    price: p.price ?? 0,
                    currencyCode: p.currencyCode,
                    maximum: p.maximum,
                    orderedCount: p.orderedCount,
                    isDynamicallyAvailable: p.isDynamicallyAvailable,
                    data: p.data,
                    type: FormHelper.fieldTypeProductType,
                    description: p.description,
                  ))
              .toList(),
          title: ffm.title ?? ffm.productType!.title ?? "",
          description: ffm.productType!.description);
    } else if (fieldType == FormHelper.fieldTypeBirthDate) {
      // Use constants from BirthDateFieldHolder instead of hardcoded strings.
      return BirthDateFieldHolder(
        id: ffm.id!,
        fieldType: ffm.type!,
        isRequired: ffm.isRequired ?? false,
        defaultValue: ffm.data?['value'],
        title: ffm.title,
        description: ffm.description,
        maxYear: ffm.data?[BirthDateFieldHolder.metaMaxYear],
        minYear: ffm.data?[BirthDateFieldHolder.metaMinYear],
        isHard: ffm.data?[BirthDateFieldHolder.metaIsHard] ?? false,
        message: ffm.data?[BirthDateFieldHolder.metaMessage] ?? '',
      );
    } else if (fieldType == FormHelper.fieldTypeIdDocument) {
      return IdDocumentFieldHolder(
        id: ffm.id!,
        fieldType: ffm.type!,
        isRequired: ffm.isRequired ?? false,
        title: ffm.title,
        description: ffm.description,
        showExpiryDate:
            ffm.data?[IdDocumentFieldHolder.metaShowExpiryDate] ?? false,
        expiryDateLabel:
            ffm.data?[IdDocumentFieldHolder.metaExpiryDateLabel]?.toString() ??
                PersonFieldsStrings.expiryDate,
      );
    } else {
      return FieldHolder(
        id: ffm.id!,
        fieldType: ffm.type!,
        isRequired: ffm.isRequired ?? false,
        title: ffm.title,
        description: ffm.description,
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      metaFields: fields.map((e) => e.toJson()).toList(),
    };
  }

  @override
  String toString() => 'FormHolder(fields: $fields)';
}
