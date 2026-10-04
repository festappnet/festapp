// Local form data for the occasion setup simulation. No database calls.
import 'dart:convert';

import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
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
  final account = BankAccountModel(
    id: 1,
    accountNumber: '123456789/0100',
    supportedCurrencies: const ['CZK'],
  );
  form.availableBankAccounts = [account];
  final productTypes = form.relatedFields
      .map((field) => field.productType)
      .whereType<ProductTypeModel>()
      .toList();
  final products =
      productTypes.expand((type) => type.products ?? <ProductModel>[]).toList();
  return FormEditBundle(
    form: form,
    formFields: form.relatedFields,
    productTypes: productTypes,
    products: products,
    availableBankAccounts: [account],
  );
}

FormModel blankDraftForm() => FormModel(
      title: 'Nový formulář',
      link: 'novy-formular',
      isOpen: false,
      occasionId: 0,
      data: {},
    );

FormModel sampleSourceForm(String occasionTitle, int year) {
  final occasion = OccasionModel(
    title: occasionTitle,
    startTime: DateTime(year, 5, 14),
    endTime: DateTime(year, 5, 16),
    isOpen: false,
    isHidden: false,
    isPromoted: false,
  );
  return FormModel(
    title: 'Registrace $year',
    link: 'registrace$year',
    occasionModel: occasion,
    occasionId: 0,
    isOpen: false,
    data: {},
    relatedFields: [
      FormFieldModel(
          title: 'Jméno',
          type: FormHelper.fieldTypeName,
          order: 0,
          isRequired: true),
      FormFieldModel(
          title: 'E-mail',
          type: FormHelper.fieldTypeEmail,
          order: 1,
          isRequired: true),
      FormFieldModel(
          title: 'Vstupenka',
          type: FormHelper.fieldTypeTicket,
          order: 2,
          isRequired: true),
      FormFieldModel(
        title: 'Vstupenky',
        type: FormHelper.fieldTypeProductType,
        order: 3,
        isTicketField: true,
        productType: ProductTypeModel(
          title: 'Vstupenky',
          products: [
            ProductModel(
                title: 'Standard',
                price: 690,
                currencyCode: 'CZK',
                maximum: 120,
                order: 0,
                data: {}),
            ProductModel(
                title: 'VIP',
                price: 1190,
                currencyCode: 'CZK',
                maximum: 30,
                order: 1,
                data: {}),
          ],
        ),
      ),
    ],
  );
}
