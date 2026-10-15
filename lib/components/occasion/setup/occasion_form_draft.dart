// Form editor adapter for database-backed occasion setup drafts.
import 'dart:convert';

import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/database_tables/tb.dart';

Map<String, dynamic> serializeDraftForm(FormEditorDraft form) {
  final data = form.toJson();
  data['fields'] = form.relatedFields.map((field) {
    final fieldData = field.toJson();
    fieldData[Tb.form_fields.product_type] = null;
    fieldData[Tb.form_fields.product_type_data] =
        field.definition.productType?.toJson();
    return fieldData;
  }).toList();
  return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(data, toEncodable: (value) {
    if (value is ProductModel) return value.toJson();
    if (value is ProductTypeModel) return value.toJson();
    throw UnsupportedError(
        'Unsupported draft form value: ${value.runtimeType}');
  })) as Map);
}

FormEditBundle draftFormBundle(Map<String, dynamic> data) {
  final form = FormEditorDraft.fromJson(Map<String, dynamic>.from(data));
  form.definition = form.definition.copyWith(occasionId: 0);
  form.definition = form.definition.copyWith(isOpen: false);
  form.availableBankAccounts = const [];
  for (final field in form.relatedFields) {
    final type = field.definition.productType;
    if (type == null) continue;
    field.definition = field.definition.copyWith(
        productType: type.copyWith(products: [
      for (final product in type.products ?? <ProductModel>[])
        product.copyWith(
            productTypeString: type.type,
            productTypeId: type.id,
            productTypeTitleString: type.title,
            deletionAllowed: true),
    ]));
  }
  final productTypes = form.relatedFields
      .map((field) => field.definition.productType)
      .whereType<ProductTypeModel>()
      .toList();
  final products =
      productTypes.expand((type) => type.products ?? <ProductModel>[]).toList();
  return FormEditBundle(
    form: form,
    productTypes: productTypes,
    products: products,
    availableBankAccounts: const [],
  );
}

FormEditorDraft defaultDraftForm(Map<String, dynamic> configuration) {
  final forms = configuration['forms'] as List? ?? [];
  if (forms.isEmpty) throw StateError('Canonical form defaults are missing');
  final draft = FormEditorDraft.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(forms.first))));
  draft.definition = draft.definition.copyWith(link: '');
  return draft;
}
