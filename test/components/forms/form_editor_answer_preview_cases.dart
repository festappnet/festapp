import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final type in ['ticket', 'text']) {
    testWidgets('hidden $type retains the correct editor visibility', (
      tester,
    ) async {
      final field = FormFieldDraft(
        id: 3470,
        type: type,
        title: 'Application block',
        data: {},
        isHidden: true,
        isRequired: true,
      );
      final bundle = FormEditBundle(
        form: FormEditorDraft(occasionId: 59, relatedFields: [field]),
        productTypes: [],
        products: [],
        availableBankAccounts: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormFieldsGenerator(bundle: bundle, editingEnabled: false),
            ),
          ),
        ),
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Application block *',
      );
      expect(title, findsOneWidget);
      final span = tester.widget<RichText>(title).text as TextSpan;
      expect(
        span.style?.decoration,
        type == 'ticket' ? isNull : TextDecoration.lineThrough,
      );
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: title, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, type == 'ticket' ? 1.0 : kHiddenOpacity);
      // Rendering must preserve the saved ticket-issuance setting.
      expect(field.definition.isHidden, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
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
    'note',
  ]) {
    testWidgets(
      '$type answer preview cannot receive input but title remains editable',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final field = FormFieldDraft(
          id: 204,
          type: type,
          title: 'Original title',
          data: {},
          isRequired: false,
        );
        final form = FormEditorDraft(occasionId: 59, relatedFields: [field]);
        final bundle = FormEditBundle(
          form: form,
          productTypes: [],
          products: [],
          availableBankAccounts: [],
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: SingleChildScrollView(
                child: FormFieldsGenerator(bundle: bundle),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        // Only the field definition's title is editable, never a sample answer.
        expect(find.byType(TextFormField), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), 'Changed title');
        await tester.pump();
        expect(field.definition.title, 'Changed title');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
