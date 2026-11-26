import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';

import '../../forms/widgets_view/form_helper.dart';
import '../../forms/models/holder_models/id_document_data.dart';
import '../models/order_admin_detail.dart';
import '../order_detail_strings.dart';
import '../order_detail_controller.dart';
import 'inline_order_field.dart';

/// Read presentation of the same field definitions used by the form designer.
/// Product fields read purchased snapshots through category identities, not a
/// fictitious answer value or the current catalogue's prices/titles.
class OrderDetailAnswers extends StatelessWidget {
  const OrderDetailAnswers({
    super.key,
    required this.detail,
    this.controller,
    this.canEdit,

    this.includeField,
  });
  final OrderDetailController? controller;
  final bool Function()? canEdit;
  final OrderAdminDetail detail;
  final bool Function(FormFieldDefinition)? includeField;

  String _label(FormFieldDefinition field) {
    final title = field.title?.trim();
    if (title != null && title.isNotEmpty && title.toLowerCase() != 'null')
      return title;
    if (field.type == FormMetadata.fieldTypeProductType &&
        field.productType?.title?.isNotEmpty == true)
      return field.productType!.title!;
    final type = field.type;
    if (type != null) {
      final label = FormHelper.fieldTypeToLocale(type);
      if (label != type) return label;
    }
    return OrderDetailStrings.text('form_field');
  }

  String _value(
    BuildContext context,
    FormFieldDefinition field,
    dynamic value,
  ) {
    if (value == null || value == '' || (value is List && value.isEmpty))
      return OrderDetailStrings.text('udaj_byl_vymazan');
    if (value is List)
      return value.map((v) => _value(context, field, v)).join(', ');
    if (field.type == FormMetadata.fieldTypeIdDocument && value is Map)
      return IdDocumentData.fromJson(Map<String, dynamic>.from(value))
          .toPreviewString(context: context);
    final option = field.options
        .where((o) => o.id == value.toString())
        .firstOrNull;
    return option?.title ??
        FormHelper.fieldTypeValue(context, value.toString(), field.type);
  }

  String _products(FormFieldDefinition field) {
    final categories = detailMap(detail.json['productCategories']);
    final purchased = detail.tickets;
    final titles = <String, int>{};
    for (final entry in purchased) {
      for (final product in detailRows(entry['snapshot']?['products'])) {
        if (categories['${product['id']}']?.toString() !=
            field.productTypeId?.toString())
          continue;
        final title = product['title']?.toString();
        if (title != null && title.isNotEmpty)
          titles.update(title, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return titles.isEmpty
        ? OrderDetailStrings.text('udaj_nebyl_uveden')
        : titles.entries
              .map((e) => e.value == 1 ? e.key : '${e.value}× ${e.key}')
              .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final values = detail.json['answers'];
    final answers = {for (final row in detailRows(values)) ...row};
    final data = {...answers};
    // Older responses stored the canonical phone only in order data. An
    // explicit empty/null response is a cleared value and must stay cleared.
    for (final field in detail.fields) {
      if (field.type == FormMetadata.fieldTypePhone &&
          field.isTicketField != true &&
          field.isHidden != true &&
          !data.containsKey('${field.id}')) {
        final phone = detail.order['data']?['phone'];
        if (phone != null) data['${field.id}'] = phone;
      }
    }
    final fields =
        detail.fields
            .where(
              (f) =>
                  (includeField?.call(f) ?? true) &&
                  f.isTicketField != true &&
                  f.type != FormMetadata.fieldTypeTicket &&
                  f.type != FormMetadata.fieldTypeSpot,
            )
            .toList()
          ..sort((a, b) {
            final order = (a.order ?? 0x7fffffff).compareTo(
              b.order ?? 0x7fffffff,
            );
            return order != 0 ? order : (a.id ?? 0).compareTo(b.id ?? 0);
          });
    final visibleNotes = fields.where(
      (field) =>
          field.type == FormMetadata.fieldTypeNote && field.isHidden != true,
    );
    final legacyNote = detail.model.toCustomerNote();
    if (visibleNotes.length == 1 && legacyNote.isNotEmpty) {
      // Older orders can have a note without its form-field answer.
      data.putIfAbsent('${visibleNotes.single.id}', () => legacyNote);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in fields)
          InlineOrderField(
            key: ValueKey(('answer', detail.model.id, field.id)),
            label:
                '${_label(field)}${field.isHidden == true ? OrderDetailStrings.text('skryte_pole') : ''}',
            value: data['${field.id}']?.toString() ?? '',
            displayValue: field.type == FormMetadata.fieldTypeProductType
                ? _products(field)
                : field.type == FormMetadata.fieldTypeNote &&
                      field.isHidden == true
                ? _value(context, field, detail.model.toCustomerNoteHidden())
                : !data.containsKey('${field.id}')
                ? OrderDetailStrings.text('udaj_nebyl_uveden')
                : _value(context, field, data['${field.id}']),
            controller: controller,
            multiline: field.type == FormMetadata.fieldTypeNote,
            keyboardType: field.type == FormMetadata.fieldTypeEmail
                ? TextInputType.emailAddress
                : field.type == FormMetadata.fieldTypePhone
                ? TextInputType.phone
                : null,
            textController: field.type == FormMetadata.fieldTypeEmail
                ? controller?.email
                : null,
            expectedAnswer: answers['${field.id}'],
            canEdit: canEdit,
            responseFieldId:
                field.id != null &&
                    field.type != FormMetadata.fieldTypeEmail &&
                    (field.type == FormMetadata.fieldTypeNote
                        ? field.isHidden != true
                        : !FormMetadata.nonEditableFields.contains(field.type))
                ? field.id
                : null,
            choices: field.type == FormMetadata.fieldTypeSelectOne
                ? field.options.map((option) => option.title).toList()
                : null,
          ),
      ],
    );
  }
}
