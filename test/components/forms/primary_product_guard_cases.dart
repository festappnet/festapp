import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/widgets_editor/product_type_editor.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

FormFieldDraft primaryField(int variants) => FormFieldDraft(
  id: 10,
  type: 'product_type',
  isTicketField: true,
  isHidden: false,
  deletionAllowed: true, // An old server response must not enable removal.
  productType: ProductTypeModel(
    id: 20,
    type: ProductModel.spotType,
    title: 'Účastnický poplatek',
    products: List.generate(
      variants,
      (index) => ProductModel(
        id: 30 + index,
        title: 'Varianta ${index + 1}',
        price: 2650,
        currencyCode: 'CZK',
        isHidden: false,
        deletionAllowed: true,
      ),
    ),
  ),
);

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  test(
    'draft cannot remove primary group or its parent, even before saving',
    () {
      final primary = primaryField(1);
      final parent = FormFieldDraft(
        id: 1,
        type: 'ticket',
        deletionAllowed: true,
      );
      final form = FormEditorDraft(
        occasionId: 1,
        relatedFields: [parent, primary],
      );
      expect(form.canDeleteField(primary), isFalse);
      expect(form.canDeleteField(parent), isFalse);
      expect(() => form.removeField(primary), throwsStateError);
      expect(() => form.removeField(parent), throwsStateError);
      expect(form.relatedFields, [parent, primary]);
      expect(form.deletedFieldIds, isEmpty);
    },
  );

  for (final variants in [1, 2]) {
    testWidgets(
      'primary group protects its last option with $variants initial variants',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final primary = primaryField(variants);
        final form = FormEditorDraft(occasionId: 1, relatedFields: [primary]);
        final proofKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: RepaintBoundary(
                key: proofKey,
                child: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setState) => ProductTypeEditor(
                      form: form,
                      ptField: primary,
                      refresh: () => setState(() {}),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete);
        expect(deleteButtons, findsNWidgets(variants + 1));
        expect(
          tester.widget<IconButton>(deleteButtons.first).onPressed,
          isNull,
        );
        expect(
          find.textContaining('deleteBlocked.primary_product'),
          findsWidgets,
        );
        if (variants == 2) {
          expect(
            tester.widget<IconButton>(deleteButtons.at(1)).onPressed,
            isNotNull,
          );
          await tester.tap(deleteButtons.at(1));
          await tester.pump();
        }
        expect(primary.definition.productType!.products, hasLength(1));
        for (final button in tester.widgetList<IconButton>(deleteButtons)) {
          expect(
            button.onPressed,
            isNull,
            reason: 'Group and final option must stay protected',
          );
        }
        final visibilityToggles = tester
            .widgetList<Switch>(find.byType(Switch))
            .where((toggle) => toggle.value)
            .toList();
        expect(visibilityToggles, hasLength(2));
        for (final toggle in visibilityToggles) {
          expect(
            toggle.onChanged,
            isNull,
            reason: 'Primary group and last option cannot be hidden',
          );
        }
        final title = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller?.text.startsWith('Varianta') == true,
        );
        await tester.enterText(title, 'Upravený název');
        await tester.pump();
        expect(
          primary.definition.productType!.products!.single.title,
          'Upravený název',
        );
        expect(tester.takeException(), isNull);
        final screenshot =
            Platform.environment['FESTAPP_PRIMARY_GUARD_SCREENSHOT'];
        if (variants == 1 && screenshot != null) {
          await tester.runAsync(() async {
            final boundary =
                proofKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
