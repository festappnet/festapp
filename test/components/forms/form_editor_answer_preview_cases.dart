import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';

void main() {
  for (final type in [
    'text',
    'email',
    'name',
    'surname',
    'phone',
    'city',
    'address',
    'nationality',
    'birth_year',
    'note'
  ]) {
    testWidgets(
        '$type answer preview cannot receive input but title remains editable',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldModel(
          id: 204,
          type: type,
          title: 'Original title',
          data: {},
          isRequired: false);
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
      expect(tester.takeException(), isNull);
      // Only the field definition's title is editable, never a sample answer.
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Changed title');
      await tester.pump();
      expect(field.title, 'Changed title');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
