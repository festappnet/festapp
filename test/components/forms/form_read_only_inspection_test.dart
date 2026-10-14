import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';
import 'package:fstapp/components/forms/widgets_editor/product_detail_editor_dialog.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_banner.dart';

void main() {
  testWidgets(
      'read-only fields and product details stay clickable without edits',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final product = ProductModel(
        id: 7,
        title: 'Admission',
        price: 590,
        maximum: 230,
        currencyCode: 'CZK',
        occasion: 59,
        description: '<p>Standing admission</p>');
    final email =
        FormFieldModel(id: 1, type: 'email', title: 'Contact', data: {});
    final tickets =
        FormFieldModel(id: 2, type: 'ticket', title: 'Participants', data: {});
    final admission = FormFieldModel(
        id: 3,
        type: 'product_type',
        isTicketField: true,
        productType:
            ProductTypeModel(id: 4, title: 'Tickets', products: [product]));
    final fields = [email, tickets, admission];
    final bundle = FormEditBundle(
        form: FormModel(occasionId: 59, relatedFields: fields),
        formFields: fields,
        productTypes: [],
        products: [product],
        availableBankAccounts: []);
    var edits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: FormFieldsGenerator(
                    bundle: bundle,
                    editingEnabled: false,
                    onChanged: () => edits++)))));
    await tester.tap(find.text('Participants', findRichText: true));
    await tester.pump();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Admission'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailEditorDialog), findsOneWidget);
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        isTrue);
    expect(
        tester
            .widget<EditableHtmlField>(find.byType(EditableHtmlField))
            .enabled,
        isFalse);
    expect(product.maximum, 230);
    expect(email.title, 'Contact');
    expect(edits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'demo panel floats over full-height content while keeping footer controls visible',
      (tester) async {
    const bodyKey = Key('body');
    const footerKey = Key('footer');
    await tester.pumpWidget(MaterialApp(
        home: DemoOccasionOverlay(
            child: Scaffold(
                body: Container(key: bodyKey, color: Colors.green),
                bottomNavigationBar:
                    const SizedBox(key: footerKey, height: 48)))));
    final page = tester.getRect(find.byType(Scaffold));
    final footer = tester.getRect(find.byKey(footerKey));
    final panel = tester.getRect(find.byType(DemoOccasionBanner));
    expect(page.height,
        tester.view.physicalSize.height / tester.view.devicePixelRatio);
    expect(panel.bottom, page.bottom - 48);
    final card = tester.getRect(find
        .descendant(
            of: find.byType(DemoOccasionBanner),
            matching: find.byType(Material))
        .first);
    expect(card.bottom, lessThanOrEqualTo(footer.top));
    expect(panel.top, lessThan(footer.bottom));
    expect(tester.getRect(find.byKey(bodyKey)).bottom, footer.top);
  });
}
