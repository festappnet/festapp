import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:festapp_core/eshop.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final allowed in [true, false]) {
    testWidgets('saved field delete button respects usage: $allowed',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldDraft(
          id: 4,
          type: 'text',
          title: 'Field',
          deletionAllowed: allowed,
          deleteBlockedReason: allowed ? null : 'responses');
      final form = FormEditorDraft(occasionId: 59, relatedFields: [field]);
      final bundle = FormEditBundle(
          form: form,
          productTypes: [],
          products: [],
          availableBankAccounts: []);
      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
    expect(FormFieldDraft().definition.canDelete, isTrue);
    expect(FormFieldDraft(id: 1).definition.canDelete, isFalse);
    expect(
        FormFieldDraft.fromJson({'id': 1, 'can_delete': true})
            .definition
            .canDelete,
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
    final ticket = FormFieldDraft(id: 1, type: 'ticket');
    final child = FormFieldDraft(id: 2, isTicketField: true);
    final freshChild = FormFieldDraft(isTicketField: true);
    final other = FormFieldDraft(id: 3, type: 'text');
    final form =
        FormEditorDraft(relatedFields: [ticket, child, freshChild, other]);
    form.removeField(ticket);
    expect(form.relatedFields, [other]);
    expect(form.toEditedJson()['deleted_field_ids'], [1, 2]);
    expect(form.toJson().containsKey('deleted_field_ids'), isFalse);
  });
}
