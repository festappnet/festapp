import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:festapp_core/forms.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/form_commands.dart';
import 'package:fstapp/components/forms/supabase_form_commands.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';

// Bundle class to hold all related data for editing a form
class FormEditBundle {
  final FormEditorDraft form;
  final List<ProductTypeModel> productTypes;
  final List<ProductModel> products;
  final List<BankAccountModel> availableBankAccounts;

  FormEditBundle({
    required this.form,
    required this.productTypes,
    required this.products,
    required this.availableBankAccounts,
  });
  factory FormEditBundle.fromData(
    Map<String, dynamic> data, {
    List<BankAccountModel>? banks,
  }) {
    // 1. Parse all individual JSON lists into Dart models.
    final form = FormEditorDraft.fromJson(data['form']);
    final formFields = (data['form_fields'] as List)
        .map((e) => FormFieldDraft.fromJson(e))
        .toList();
    final productTypes = (data['product_types'] as List)
        .map((e) => ProductTypeModel.fromJson(e))
        .toList();
    final products = (data['products'] as List)
        .map((e) => ProductModel.fromJson(e))
        .toList();
    final availableBankAccounts =
        banks ??
        (data['available_bank_accounts'] as List)
            .map((e) => BankAccountModel.fromJson(e))
            .toList();

    // 2. Interconnect the parsed models.
    // Create maps for efficient lookups.
    final catalog = ProductCatalog(products: products, types: productTypes);
    final productTypeMap = {for (final type in catalog.types) type.id: type};

    // Link product type data to the relevant form fields.
    for (var field in formFields) {
      if (field.definition.productTypeId != null) {
        field.definition = field.definition.copyWith(
          productType: productTypeMap[field.definition.productTypeId],
        );
      }
    }

    // Assign the fully populated fields list to the form.
    form.relatedFields = formFields;
    form.captureProductCatalog(catalog.types);

    // Find and assign the selected bank account model to the form.
    if (availableBankAccounts.isNotEmpty) {
      form.availableBankAccounts = availableBankAccounts;
      if (form.definition.bankAccountId != null) {
        form.bankAccount = availableBankAccounts.firstWhereOrNull(
          (ba) => ba.id == form.definition.bankAccountId,
        );
      }
    }

    // 3. Create and return the final bundle.
    return FormEditBundle(
      form: form,
      productTypes: catalog.types,
      products: products,
      availableBankAccounts: availableBankAccounts,
    );
  }

  factory FormEditBundle.fromSave(
    FormEditorDraft original,
    Map<String, dynamic> response,
  ) {
    final state = Map<String, dynamic>.from(response['authoring'] as Map);
    final bundle = FormEditBundle.fromData({
      'form': {
        ...Map<String, dynamic>.from(state['form']),
        'key': original.definition.key,
        'link': response['link'],
      },
      'form_fields': state['fields'],
      'product_types': state['productTypes'],
      'products': state['products'],
      'available_bank_accounts': const [],
    }, banks: original.availableBankAccounts ?? const []);
    bundle.form.occasionModel = original.occasionModel;
    final previous = original.toEditedJson();
    Map<String, dynamic> versions(
      String before,
      String alive,
      String related,
    ) => {
      for (final entry in (previous[before] as Map).entries)
        if ((response[alive] as Map).containsKey(entry.key))
          entry.key as String: entry.value,
      ...Map<String, dynamic>.from(state[related]),
    };
    // A receipt advances only acknowledged products. Cached unrelated choices
    // keep their original versions, so a later edit cannot silently rebase them.
    bundle.form.acceptProductVersions({
      'product_versions': versions(
        'expected_product_versions',
        'product_versions',
        'productVersions',
      ),
      'product_type_versions': versions(
        'expected_product_type_versions',
        'product_type_versions',
        'productTypeVersions',
      ),
    });
    return bundle;
  }

  FormEditBundle afterSave(FormEditorDraft saved) {
    final versions = saved.toEditedJson();
    final types = {
      for (final type in productTypes)
        if ((versions['expected_product_type_versions'] as Map).containsKey(
          type.id.toString(),
        ))
          type.id: type,
      for (final field in saved.relatedFields)
        if (field.definition.productType != null)
          field.definition.productType!.id: field.definition.productType!,
    };
    final rows = {
      for (final product in products)
        if ((versions['expected_product_versions'] as Map).containsKey(
          product.id.toString(),
        ))
          product.id: product,
      for (final type in types.values)
        if (saved.relatedFields.any(
          (field) => field.definition.productTypeId == type.id,
        ))
          for (final product in type.products ?? const <ProductModel>[])
            product.id: product,
    };
    return FormEditBundle(
      form: saved,
      productTypes: types.values.toList(),
      products: rows.values.toList(),
      availableBankAccounts: availableBankAccounts,
    );
  }
}

class DbForms {
  static Future<BlueprintLayoutSaveResult> saveLayoutSnapshot(
    BlueprintLayoutSaveRequest request,
  ) async => BlueprintLayoutSaveResult.fromJson(
    await _commands.saveBlueprint(request.toJson()),
  );

  static FormCommands blueprintCommands() => _commands;

  static final _supabase = Supabase.instance.client;
  static FormCommands get _commands => SupabaseFormCommands(_supabase);

  static Future<List<FormBundle>> getAllFormsForOccasionOrUnit() async {
    final response = await _supabase.rpc('get_all_viewable_forms_for_copying');

    return List<FormBundle>.from(response.map((f) => FormBundle.fromJson(f)));
  }

  static Future<void> duplicateFormToOccasion({
    required int sourceFormId,
    required String targetOccasionLink,
    required String locale,
  }) async {
    await _commands.duplicate(
      sourceFormId: sourceFormId,
      targetOccasionLink: targetOccasionLink,
      locale: locale,
    );
  }

  static Future<List<FormBundle>> getAllFormsByOccasionLink(
    String occasionLink, {
    String? formLink,
  }) async {
    final response = await _supabase.rpc(
      'get_forms_by_link',
      params: {'occasion_link': occasionLink, 'form_link': ?formLink},
    );

    return List<FormBundle>.from(response.map((f) => FormBundle.fromJson(f)));
  }

  static Future<({List<FormBundle> forms, String canonical})> getFormsForRoute(
    String occasionLink,
    String formLink,
  ) async {
    final rows = await _supabase.rpc(
      'get_forms_by_link',
      params: {'occasion_link': occasionLink, 'form_link': formLink},
    ) as List;
    final resolved = rows.where((row) => row['requested_link'] == formLink);
    return (
      forms: rows
          .map((row) => FormBundle.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      canonical: resolved.isEmpty ? formLink : resolved.first['link'] as String,
    );
  }

  static Future<void> createNewForm({
    required String title,
    required String link,
    required String occasionLink,
  }) async {
    await _commands.create(
      title: title,
      link: link,
      occasionLink: occasionLink,
    );
  }

  static Future<FormEditorDraft> updateForm(FormEditorDraft form) async {
    final response = await _commands.save(form.toEditedJson());
    return FormEditBundle.fromSave(form, response).form;
  }

  static Future<void> deleteForm(
    int formId, {
    required int expectedVersion,
  }) async {
    await _commands.delete(formId, expectedVersion: expectedVersion);
  }

  static Future<FormBundle?> getFormFromLink(String link) async {
    final response = await _supabase.rpc(
      'get_form_by_link',
      params: {'form_link': link},
    );

    if (response["code"] == 200 || response["code"] == 400) {
      var form = FormBundle.fromJson(response["data"]);
      return form;
    }
    return null;
  }

  static Future<FormEditBundle?> getFormForEdit(String link) async {
    final response = await _supabase.rpc(
      'get_form_for_edit',
      params: {'form_link': link},
    );

    if (response["code"] != 200) {
      // You can add more robust error handling here, e.g., logging or showing a toast.

      return null;
    }

    final data = response["data"];

    return FormEditBundle.fromData(Map<String, dynamic>.from(data));
  }

  static Future<BlueprintModel?> getBlueprint(
    String mySecret,
    String formKey,
    int blueprintId,
  ) async {
    final response = await _supabase.rpc(
      'get_blueprint',
      params: {
        'my_secret': mySecret,
        'form_key': formKey,
        'blueprint_id': blueprintId,
      },
    );

    if (response["code"] != 200) {
      return null;
    }

    var b = BlueprintModel.fromJson(response["data"]);
    b.assignAllSpotsWithBlueprint();
    return b;
  }

  static Future<BlueprintModel?> getBlueprintForEdit(
    String occasionLink,
  ) async {
    final response = await _supabase.rpc(
      'get_blueprint_for_edit',
      params: {'occasion_link': occasionLink},
    );

    if (response["code"] != 200) {
      return null;
    }

    var b = BlueprintModel.fromJson(response["data"]);
    b.assignAllSpotsWithBlueprint();
    return b;
  }

  static Future<List<FormFieldDefinition>> getAllFormFields(
    String formLink,
  ) async {
    final response = await _supabase.rpc(
      'get_all_form_fields',
      params: {'form_link': formLink},
    );

    return List<FormFieldDefinition>.from(
      (response as List).map((x) => FormFieldDefinition.fromJson(x)),
    );
  }
}
