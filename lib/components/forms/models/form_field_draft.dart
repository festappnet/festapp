import 'package:festapp_core/forms.dart';
import 'package:festapp_core/eshop.dart';
import 'form_option_draft.dart';

/// One editor-owned field snapshot, plus mutable option drafts. Persisted values
/// are assembled only at the explicit freeze/save boundary.
class FormFieldDraft {
  FormFieldDefinition definition;
  final List<FormOptionDraft> options;
  FormFieldDraft(
      {int? id,
      String? deleteBlockedReason,
      bool? deletionAllowed,
      DateTime? createdAt,
      DateTime? updatedAt,
      String? title,
      String? description,
      String? type,
      bool? isRequired,
      bool? isHidden,
      bool? isTicketField,
      int? form,
      int? order,
      int? productTypeId,
      dynamic data,
      ProductTypeModel? productType,
      List<FormOptionDraft>? options})
      : definition = FormFieldDefinition(
            id: id,
            deleteBlockedReason: deleteBlockedReason,
            deletionAllowed: deletionAllowed,
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: title,
            description: description,
            type: type,
            isRequired: isRequired,
            isHidden: isHidden,
            isTicketField: isTicketField,
            form: form,
            order: order,
            productTypeId: productTypeId,
            data: data,
            productType: productType),
        options = List.of(options ?? const []);

  FormFieldDraft.fromDefinition(FormFieldDefinition value)
      : definition = value.copyWith(options: const <FormOptionDefinition>[]),
        options = value.options.map(FormOptionDraft.fromDefinition).toList();
  factory FormFieldDraft.fromJson(Map<String, dynamic> json) =>
      FormFieldDraft.fromDefinition(FormFieldDefinition.fromJson(json));
  bool get isPrimaryProductGroup =>
      definition.type == FormMetadata.fieldTypeProductType &&
      definition.productType?.type == ProductModel.spotType;

  bool canRemovePrimaryVariantAt(int index) =>
      !isPrimaryProductGroup ||
      definition.productType!.products!.asMap().entries.any(
        (entry) => entry.key != index && entry.value.isHidden != true,
      );

  bool get hasInvalidSelectionOptions =>
      (definition.type == FormMetadata.fieldTypeSelectOne ||
          definition.type == FormMetadata.fieldTypeSelectMany) &&
      (options.isEmpty || options.any((option) => option.title.trim().isEmpty));

  FormFieldDefinition freeze() => definition.copyWith(
      options: options.map((option) => option.freeze()).toList());
  Map<String, dynamic> toJson() => freeze().toJson();
}
