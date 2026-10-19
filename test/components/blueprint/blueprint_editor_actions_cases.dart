import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/blueprint/blueprint_configuration.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_controls_bar.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() {
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  testWidgetsWithEnvironment(() => _environment,
      'seat plan resize enables saving and discard restores the plan',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plan = BlueprintModel(
        configuration: BlueprintConfiguration(width: 2, height: 2),
        groups: [],
        objects: [],
        products: []);
    await _environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintTab.prototype(
                prototypeBlueprint: plan, onPrototypeSave: (_) {})));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, CommonStrings.save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find
        .descendant(
            of: find.byType(BlueprintControlsBar),
            matching: find.byIcon(Icons.add))
        .first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(plan.configuration!.width, 2,
        reason: 'the saved prototype must not mutate with the draft');
    await tester.tap(find.descendant(
        of: find.byType(EditorActionBar), matching: find.byType(TextButton)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, CommonStrings.discardChanges));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.byType(BlueprintTab), findsOneWidget);
  });
}
