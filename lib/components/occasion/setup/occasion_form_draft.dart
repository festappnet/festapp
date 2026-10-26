// Form editor adapter for database-backed occasion setup drafts.
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../features/feature.dart';
import '../../features/feature_constants.dart';
import '../occasion_model.dart';
import '../occasion_sale_strings.dart';

import 'package:festapp_core/eshop.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/database_tables/tb.dart';

Map<String, dynamic> serializeDraftForm(FormEditorDraft form) {
  final types = form.relatedFields
      .map((field) => field.definition.productType)
      .whereType<ProductTypeModel>();
  final usedIds = <int>{
    for (final type in types)
      if (type.id != null) type.id!,
    for (final product
        in types.expand((type) => type.products ?? <ProductModel>[]))
      if (product.id != null) product.id!,
  };
  int nextId() {
    int id;
    do {
      // Stay exact in JavaScript JSON, without reusing a removed row's ID on
      // reload and accidentally adopting its pending price/ticket references.
      id = -int.parse(const Uuid().v4().replaceAll('-', '').substring(0, 13),
          radix: 16);
    } while (id == 0 || !usedIds.add(id));
    return id;
  }

  // New editor rows need stable local identities before other draft settings
  // (price waves, seating and ticket references) can point to them.
  for (final field in form.relatedFields) {
    final type = field.definition.productType;
    if (type == null) continue;
    final localTypeId = type.id ?? nextId();
    final currency = type.products
            ?.map((product) => product.currencyCode)
            .whereType<String>()
            .where((code) => code.isNotEmpty)
            .firstOrNull ??
        'CZK';
    field.definition = field.definition.copyWith(
        productType: ProductTypeModel(
      id: localTypeId,
      aggregateVersion: type.aggregateVersion,
      title: type.title,
      description: type.description,
      type: type.type,
      data: type.data,
      occasion: type.occasion,
      products: [
        for (final product in type.products ?? <ProductModel>[])
          product.copyWith(
              id: product.id ?? nextId(),
              productTypeId: localTypeId,
              currencyCode: (product.currencyCode ?? '').isEmpty
                  ? currency
                  : product.currencyCode)
      ],
    ));
  }
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
  // A prototype owns its feature context; unrelated current occasions must
  // never decide whether this draft exposes a quantity setting.
  form.occasionModel = OccasionModel(
      id: 0,
      isOpen: false,
      isHidden: true,
      isPromoted: false,
      features: [
        SimpleFeature(
            code: FeatureConstants.ticket,
            isEnabled: form.relatedFields.any((f) =>
                f.definition.type == 'ticket' &&
                f.definition.isHidden != true)),
        SimpleFeature(
            code: FeatureConstants.blueprint,
            isEnabled: form.usesSeatSelection),
      ]);
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
  return localizeStarterProducts(draft);
}

FormEditorDraft localizeStarterProducts(FormEditorDraft draft) {
  // Only the generated starter is renamed. Existing source products retain
  // their organizer-owned titles, IDs, prices and order limits.
  for (final field in draft.relatedFields) {
    final type = field.definition.productType;
    if (type?.type != 'spot' || type?.title != 'Spot') continue;
    field.definition = field.definition.copyWith(
      title: OccasionSaleStrings.text('admission'),
      productType: type!
          .copyWith(title: OccasionSaleStrings.text('admission'), products: [
        for (final product in type.products ?? <ProductModel>[])
          product.title == 'Variant 1'
              ? product.copyWith(
                  title: OccasionSaleStrings.text('standardTicket'))
              : product,
      ]),
    );
  }
  return draft;
}

/// Explicit blueprint intent uses the existing public form's seat field.
void setDraftSeatSelection(Map<String, dynamic> data, bool enabled) {
  final form = data['formDraft'];
  if (form is! Map) return;
  final fields = form['fields'] as List? ?? [];
  final spot = fields
      .whereType<Map>()
      .where((f) => f['type'] == 'spot' && f['is_ticket_field'] == true)
      .firstOrNull;
  if (spot != null) {
    spot['is_hidden'] = !enabled;
  } else if (enabled &&
      fields.whereType<Map>().any((f) => f['type'] == 'ticket')) {
    fields.add({
      'type': 'spot',
      'is_ticket_field': true,
      'is_hidden': false,
      'is_required': true,
      'title': OccasionSaleStrings.text('seatSelection'),
      'order': fields.length
    });
  }
}

/// The displayed default does not become a form override on unrelated edits.
int effectiveSetupDeadlineSeconds(Map<String, dynamic> data) {
  final raw = (data['deadline'] as String? ?? '').trim();
  final days = int.tryParse(raw);
  final features = (((data['defaultConfiguration'] as Map?)?['occasion']
              as Map?)?['features'] as List? ??
          [])
      .whereType<Map>();
  final inherited = features
      .where((f) => f['code'] == 'form')
      .firstOrNull?['deadline_duration_seconds'] as num?;
  return FormDefinition(
          deadlineDurationSeconds: days == null ? null : days * 86400)
      .effectiveDeadlineDurationSeconds(occasionDefault: inherited?.toInt());
}
