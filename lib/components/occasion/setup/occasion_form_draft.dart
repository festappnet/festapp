// Form editor adapter for database-backed occasion setup drafts.
import 'dart:convert';

import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/database_tables/tb.dart';

Map<String, dynamic> serializeDraftForm(FormModel form) {
  final data = form.toJson();
  data['fields'] = form.relatedFields.map((field) {
    final fieldData = field.toJson();
    fieldData[Tb.form_fields.product_type] = null;
    fieldData[Tb.form_fields.product_type_data] = field.productType?.toJson();
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
  final form = FormModel.fromJson(Map<String, dynamic>.from(data));
  form.occasionId = 0;
  form.isOpen = false;
  form.availableBankAccounts = const [];
  final productTypes = form.relatedFields
      .map((field) => field.productType)
      .whereType<ProductTypeModel>()
      .toList();
  final products =
      productTypes.expand((type) => type.products ?? <ProductModel>[]).toList();
  for (final type in productTypes) {
    for (final product in type.products ?? <ProductModel>[]) {
      product.productTypeString = type.type;
      product.productTypeId = type.id;
      product.productTypeTitleString = type.title;
      product.deletionAllowed = true;
    }
  }
  return FormEditBundle(
    form: form,
    formFields: form.relatedFields,
    productTypes: productTypes,
    products: products,
    availableBankAccounts: const [],
  );
}

FormModel defaultDraftForm(Map<String, dynamic> configuration) {
  final forms = configuration['forms'] as List? ?? [];
  if (forms.isEmpty) throw StateError('Canonical form defaults are missing');
  return FormModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(forms.first))))
    ..link = '';
}
