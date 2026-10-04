import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';

void main() {
  test('blueprint products stay out of regular form and ticket choices', () {
    final spotType = ProductTypeModel(type: ProductModel.spotType, products: [
      ProductModel(id: 10, title: 'Seat', price: 450),
    ]);
    final form = FormModel(relatedFields: [
      FormFieldModel(id: 1, type: FormHelper.fieldTypeTicket),
      FormFieldModel(
        id: 5,
        type: FormHelper.fieldTypeSpot,
        isTicketField: true,
        isHidden: false,
      ),
      FormFieldModel(
        id: 2,
        type: FormHelper.fieldTypeProductType,
        isTicketField: true,
        productType: spotType,
      ),
      FormFieldModel(
        id: 3,
        type: FormHelper.fieldTypeProductType,
        isTicketField: true,
        productType: ProductTypeModel(products: [
          ProductModel(id: 11, title: 'Meal', price: 100),
        ]),
      ),
      FormFieldModel(
        id: 4,
        type: FormHelper.fieldTypeProductType,
        productType: spotType,
      ),
    ]);
    final holder = FormHolder.fromFormFieldModel(form);
    expect(holder.fields.map((field) => field.id), [1]);
    expect(holder.getTicket()!.fields.map((field) => field.id), [5, 3]);
  });
  test('reading design and schedule defaults does not create an unsaved change',
      () {
    final form = FormModel(data: {});
    expect(form.startTime, isNull);
    expect(form.endTime, isNull);
    expect(form.enableCountdown, false);
    expect(form.primaryColor, isNull);
    expect(form.fontFamily, isNull);
    expect(form.data, isEmpty);
    form.primaryColor = 0xff123456;
    form.enableCountdown = true;
    expect(form.primaryColor, 0xff123456);
    expect(form.enableCountdown, true);
  });
  test('festapp2025 metadata loads and saves as an object', () {
    final form = FormModel.fromJson({
      'id': 22,
      'occasion': 59,
      'link': 'festapp2025',
      'data': [
        null,
        {'phone_prefixes': null}
      ],
    });
    expect(form.startTime, isNull);
    expect(form.data!['phone_prefixes'], isNull);
    expect(form.toJson()['data'], isA<Map<String, dynamic>>());
  });

  test('concatenated metadata preserves settings in merge order', () {
    final form = FormModel.fromJson({
      'data': [
        {
          'design': {'primary_color': '#123456'},
          'custom': 'first'
        },
        null,
        {
          'custom': 'last',
          'phone_prefixes': ['+420']
        },
      ],
    });
    expect(form.data!['design'], {'primary_color': '#123456'});
    expect(form.data!['custom'], 'last');
    expect(form.data!['phone_prefixes'], ['+420']);
  });

  test('object and absent metadata keep their existing contract', () {
    expect(
        FormModel.fromJson({
          'data': {'custom': 1}
        }).data,
        {'custom': 1});
    expect(FormModel.fromJson({'data': null}).data, isNull);
  });
}
