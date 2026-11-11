import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_navigation_controller.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() {
    _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
  });

  testWidgetsWithEnvironment(
    () => _environment,
    'outline follows draft identity through rename reorder insert delete and bundle replacement',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigation = FormFieldsNavigationController();
      addTearDown(navigation.dispose);
      final first = FormFieldDraft(id: 1, type: 'text', title: 'Jméno');
      final second = FormFieldDraft(id: 2, type: 'text', title: 'Příjmení');
      final added = FormFieldDraft(
        type: 'text',
        title: 'Doprovod',
        deletionAllowed: true,
      );
      var bundle = FormEditBundle(form: FormEditorDraft(
        occasionId: 59,
        relatedFields: [
          first,
          second,
          FormFieldDraft(
            id: 3,
            type: 'text',
            title: 'Podřízené',
            isTicketField: true,
          ),
        ],
      ), productTypes: [], products: [], availableBankAccounts: []);
      late StateSetter rebuild;
      var changes = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SingleChildScrollView(
                  child: FormFieldsGenerator(
                    bundle: bundle,
                    navigationController: navigation,
                    onChanged: () => changes++,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(navigation.fields.map((item) => item.field), [first, second]);
      navigation.revealField(second);
      await tester.pumpAndSettle();
      final selected = navigation.selectedIdentity;
      expect(selected, navigation.fields[1].identity);
      expect(changes, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Příjmení'),
        'Příjmení účastníka',
      );
      await tester.pumpAndSettle();
      expect(navigation.fields[1].title, 'Příjmení účastníka');
      expect(navigation.selectedIdentity, selected);
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorder!(0, 2);
      await tester.pumpAndSettle();
      expect(navigation.fields.map((item) => item.field), [second, first]);
      expect(navigation.selectedIdentity, selected);
      rebuild(() => bundle.form.relatedFields.add(added));
      await tester.pumpAndSettle();
      final addedIdentity = navigation.fields.last.identity;
      navigation.revealField(added);
      await tester.pumpAndSettle();
      expect(navigation.selectedIdentity, addedIdentity);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Doprovod'),
        'Host',
      );
      await tester.pumpAndSettle();
      expect(navigation.fields.last.identity, addedIdentity);
      expect(navigation.fields.last.title, 'Host');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete));
      await tester.pumpAndSettle();
      expect(navigation.fields.map((item) => item.field), [second, first]);
      navigation.revealField(added);
      await tester.pumpAndSettle();
      expect(navigation.selectedIdentity, isNot(addedIdentity));
      navigation.revealField(first);
      rebuild(
        () => bundle = FormEditBundle(form: FormEditorDraft(
          occasionId: 60,
          relatedFields: [
            FormFieldDraft(id: 1, type: 'text', title: 'Nový formulář'),
          ],
        ), productTypes: [], products: [], availableBankAccounts: []),
      );
      await tester.pumpAndSettle();
      expect(navigation.fields.single.title, 'Nový formulář');
      navigation.revealField(first);
      await tester.pumpAndSettle();
      expect(navigation.fields.single.title, 'Nový formulář');
      navigation.revealField(navigation.fields.single.field);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(navigation.fields, isEmpty);
      expect(tester.takeException(), isNull);
      expect(changes, greaterThan(0));
    },
  );
  for (final width in [320.0, 390.0, 600.0, 1000.0]) {
    testWidgetsWithEnvironment(() => _environment,
        'field actions stay accessible in one row at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldDraft(
        id: 4,
        type: 'text',
        title: 'Poznámka',
        deletionAllowed: true,
      );
      final form = FormEditorDraft(occasionId: 59, relatedFields: [field]);
      final bundle = FormEditBundle(
        form: form,
        productTypes: [],
        products: [],
        availableBankAccounts: [],
      );
      await _environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormFieldsGenerator(bundle: bundle),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final isCompact = width - 24 < 600;
      final delete = find.widgetWithIcon(IconButton, Icons.delete);
      final menu = find.widgetWithIcon(
        PopupMenuButton<String>,
        Icons.more_vert,
      );
      expect(delete, isCompact ? findsNothing : findsOneWidget);
      final action = isCompact ? menu : delete;
      final rect = tester.getRect(action);
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
      expect(field.definition.isHidden, isTrue);
      expect(tester.getRect(action), rect);
      await tester.tap(action);
      if (isCompact) {
        await tester.pumpAndSettle();
        final deleteItem = find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> && widget.value == 'delete_field',
        );
        expect(
          tester.widget<PopupMenuItem<String>>(deleteItem).enabled,
          isTrue,
        );
        await tester.tap(deleteItem);
      }
      await tester.pump();
      expect(form.relatedFields, isEmpty);
      expect(form.deletedFieldIds, {4});
    });
  }
  testWidgetsWithEnvironment(
    () => _environment,
    'mobile delete menu explains why a used field cannot be deleted',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldDraft(
        id: 4,
        type: 'text',
        title: 'Poznámka',
        deletionAllowed: false,
        deleteBlockedReason: 'responses',
      );
      final form = FormEditorDraft(occasionId: 59, relatedFields: [field]);
      await _environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormFieldsGenerator(
                bundle: FormEditBundle(
                  form: form,
                  productTypes: [],
                  products: [],
                  availableBankAccounts: [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.widgetWithIcon(PopupMenuButton<String>, Icons.more_vert),
      );
      await tester.pumpAndSettle();
      final deleteItem = find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == 'delete_field',
      );
      expect(tester.widget<PopupMenuItem<String>>(deleteItem).enabled, isFalse);
      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: deleteItem, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, isNotEmpty);
      await tester.tap(deleteItem);
      await tester.pump();
      expect(form.relatedFields, [field]);
      expect(form.deletedFieldIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
