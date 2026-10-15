import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';

void main() {
  for (final allowed in [true, false]) {
    testWidgets('saved field delete button respects usage: $allowed',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldModel(
          id: 4,
          type: 'text',
          title: 'Field',
          deletionAllowed: allowed,
          deleteBlockedReason: allowed ? null : 'responses');
      final form = FormModel(occasionId: 59, relatedFields: [field]);
      final bundle = FormEditBundle(
          form: form,
          formFields: [field],
          productTypes: [],
          products: [],
          availableBankAccounts: []);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: FormFieldsGenerator(bundle: bundle)))));
      final buttonFinder = find.widgetWithIcon(IconButton, Icons.delete);
      final button = tester.widget<IconButton>(buttonFinder);
      expect(button.onPressed != null, allowed);
      if (allowed) {
        await tester.tap(buttonFinder);
        await tester.pump();
        expect(form.relatedFields, isEmpty);
        expect(form.deletedFieldIds, {4});
      } else {
        expect(button.tooltip, contains('responses'));
        expect(form.relatedFields, [field]);
        expect(form.deletedFieldIds, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  test('server usage controls saved items; unknown usage fails closed', () {
    expect(FormFieldModel().canDelete, isTrue);
    expect(FormFieldModel(id: 1).canDelete, isFalse);
    expect(FormFieldModel.fromJson({'id': 1, 'can_delete': true}).canDelete,
        isTrue);
    final product = ProductModel.fromJson({
      'id': 3,
      'can_delete': false,
      'delete_blocked_reason': 'blueprint',
    });
    expect(product.canDelete, isFalse);
    expect(product.deleteBlockedReason, 'blueprint');
    expect(ProductModel().canDelete, isTrue);
    expect(ProductModel(id: 3).canDelete, isFalse);
  });

  test('ticket removal stages nested deletions only in the save payload', () {
    final ticket = FormFieldModel(id: 1, type: 'ticket');
    final child = FormFieldModel(id: 2, isTicketField: true);
    final freshChild = FormFieldModel(isTicketField: true);
    final other = FormFieldModel(id: 3, type: 'text');
    final form = FormModel(relatedFields: [ticket, child, freshChild, other]);
    form.removeField(ticket);
    expect(form.relatedFields, [other]);
    expect(form.toEditedJson()['deleted_field_ids'], [1, 2]);
    expect(form.toJson().containsKey('deleted_field_ids'), isFalse);
  });
}
