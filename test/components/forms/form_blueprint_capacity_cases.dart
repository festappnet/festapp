import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/forms/views/form_capacity_settings.dart';
import 'package:flutter/foundation.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

late ValueNotifier<({int accountId, int revision})> _bankChanges;
void main() {
  setUp(() {
    _bankChanges = ValueNotifier((accountId: 0, revision: 0));
    addTearDown(_bankChanges.dispose);
  });
  WidgetEnvironmentFixture.register();
  setUpAll(
    () => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    ),
  );
  for (final enabled in [false, true]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'stored blueprint with feature enabled=$enabled',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [
              FormFeature(code: 'form'),
              SimpleFeature(code: 'blueprint', isEnabled: enabled),
            ],
          ),
        );
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        final form = FormEditorDraft(
          link: 'test',
          title: 'Test',
          blueprint: 42,
        );
        FormEditorDraft? saved;
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: FormCapacitySettings(
                form: form,
                canEdit: true,
                onChanged: () => saved = form,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ListTile>(find.byType(ListTile).first).enabled,
          !enabled,
        );
        if (!enabled) {
          await tester.tap(find.byType(ListTile).first);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SwitchListTile).first);
          await tester.pumpAndSettle();
          final capacity = find.widgetWithText(
            TextFormField,
            WaitlistStrings.capacity,
          );
          await tester.enterText(capacity, '50');
          await tester.tap(find.text(WaitlistStrings.applySettings));
          await tester.pumpAndSettle();
          expect(saved?.definition.participantCapacity, 50);
          expect(saved?.definition.blueprint, 42);
          await tester.pump(const Duration(seconds: 4));
        }
      },
    );
  }
}
