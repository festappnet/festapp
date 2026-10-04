import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';

void main() {
  setUpAll(() {
    Localization.load(
      const Locale('cs'),
      translations: Translations(
        jsonDecode(File('assets/translations/cs.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
  });

  for (final width in [320.0, 390.0, 600.0, 1000.0]) {
    testWidgets('field delete is visible and tappable at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldModel(
        id: 4,
        type: 'text',
        title: 'Poznámka',
        deletionAllowed: true,
      );
      final form = FormModel(occasionId: 59, relatedFields: [field]);
      final bundle = FormEditBundle(
        form: form,
        formFields: [field],
        productTypes: [],
        products: [],
        availableBankAccounts: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormFieldsGenerator(bundle: bundle),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final delete = find.widgetWithIcon(IconButton, Icons.delete);
      final rect = tester.getRect(delete);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
      final typeMenu = find.byType(PopupMenuButton<String>).first;
      final checkbox = find.byType(Checkbox);
      final visibilitySwitch = find.byType(Switch);
      expect(tester.getRect(typeMenu).center.dy, rect.center.dy);
      expect(tester.getRect(checkbox).center.dy, rect.center.dy);
      expect(tester.getRect(visibilitySwitch).center.dy, rect.center.dy);
      final horizontalScroll = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.right,
          )
          .last;
      await tester.drag(horizontalScroll, const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(visibilitySwitch);
      await tester.pump();
      expect(field.isHidden, isTrue);
      expect(tester.getRect(delete), rect);
      await tester.tap(delete);
      await tester.pump();
      expect(form.relatedFields, isEmpty);
      expect(form.deletedFieldIds, {4});
    });
  }
}
