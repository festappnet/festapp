import 'dart:async';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fstapp/components/_shared/editor_file_drop_region.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/drop_file.dart';
import '../../support/editor_file_drop.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_strings.dart';
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
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (_) async => true);
  });
  testWidgetsWithEnvironment(() => _environment,
      'prototype SVG menu and body drop share draft import; raster upload stays blocked',
      (tester) async {
    tester.view.physicalSize = const Size(2800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const original =
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>';
    const replacement =
        '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"></svg>';
    final plan = BlueprintModel(
        backgroundSvg: original,
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
    final dynamic state = tester.state(find.byType(BlueprintTab));
    final point = tester.getCenter(find.byType(EditorFileDropRegion));
    await pluginDrop(
        tester, point, [droppedFile('new.svg', utf8.encode(replacement))]);
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, replacement);
    final save = find.widgetWithText(
        FilledButton, OccasionSetupStrings.story('saveAndReturn'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await state.loadData();
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, original);
    await state.importBackground(XFile.fromData(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        name: 'new.png'));
    expect(state.blueprint.backgroundSvg, original);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.uploadImage), findsNothing);
    await tester.tap(find.text(BlueprintStrings.uploadSVG));
    await tester.pumpAndSettle();
    await pluginDrop(tester, tester.getCenter(find.byType(DropFile)),
        [droppedFile('new.svg', utf8.encode(replacement))]);
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, original,
        reason: 'dialog is the only drop recipient');
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.ok));
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, replacement);
    await state.importBackground(XFile.fromData(
        Uint8List.fromList(utf8.encode('invalid')),
        name: 'invalid.svg'));
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, replacement);
    await state.saveChanges();
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, replacement);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgetsWithEnvironment(() => _environment,
      'raster host imports once, blocks conflicting actions and retains previous background on failure',
      (tester) async {
    final previousRights = RightsService.occasionLinkModel;
    addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = previousRights);
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(occasionUser: OccasionUserModel(isEditor: true));
    tester.view.physicalSize = const Size(2800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original =
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>';
    final replacement =
        'data:image/png;base64,${base64Encode(File('test/fixtures/ticket_layout/background.png').readAsBytesSync())}';
    final pending = Completer<String>();
    var calls = 0;
    var loads = 0;
    var fail = false;
    await _environment.pumpWidget(
        tester,
        MaterialApp(
            home: MediaQuery(
                data: const MediaQueryData(
                    size: Size(2800, 1200), textScaler: TextScaler.linear(.6)),
                child: BlueprintTab(
                  loadBlueprint: () async {
                    loads++;
                    return BlueprintModel(
                        occasion: 1,
                        backgroundSvg: original,
                        configuration:
                            BlueprintConfiguration(width: 2, height: 2),
                        groups: [],
                        objects: [],
                        products: []);
                  },
                  uploadBackground: (bytes, occasion) {
                    calls++;
                    if (fail) throw StateError('upload failed');
                    return pending.future;
                  },
                ))));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(BlueprintTab));
    final point = tester.getCenter(find.byType(EditorFileDropRegion));
    final file = droppedFile('new.png', [137, 80, 78, 71, 13, 10, 26, 10]);
    await pluginDrop(tester, point, [file]);
    await pluginDrop(tester, point, [file]);
    expect(calls, 1);
    await state.loadData();
    await state.saveChanges();
    expect(loads, 1);
    expect(state.blueprint.backgroundSvg, original);
    pending.complete(replacement);
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, replacement);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, CommonStrings.save))
            .onPressed,
        isNotNull);
    final oversized = OversizedEditorImage();
    await state.importBackground(oversized);
    expect(oversized.read, isFalse);
    expect(calls, 1);
    fail = true;
    await pluginDrop(tester, point, [file]);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(state.blueprint.backgroundSvg, replacement);
    await state.loadData();
    await tester.pumpAndSettle();
    expect(state.blueprint.backgroundSvg, original);
    RightsService.occasionLinkModelNotifier.value = null;
    await pluginDrop(tester, point, [file]);
    expect(calls, 2, reason: 'handler rechecks permissions');
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgetsWithEnvironment(() => _environment,
      'prototype completes only after durable save and baseline acceptance',
      (tester) async {
    tester.view.physicalSize = const Size(2800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<void>();
    var completed = 0;
    var fail = true;
    final plan = BlueprintModel(
        configuration: BlueprintConfiguration(width: 2, height: 2),
        groups: [],
        objects: [],
        products: []);
    await _environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintTab.prototype(
          prototypeBlueprint: plan,
          onPrototypeSave: (_) async {
            if (fail) throw StateError('save failed');
            await pending.future;
          },
          onPrototypeComplete: () => completed++,
        )));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(BlueprintTab));
    await tester.tap(find
        .descendant(
            of: find.byType(BlueprintControlsBar),
            matching: find.byIcon(Icons.add))
        .first);
    await tester.pumpAndSettle();
    expect(plan.configuration!.width, 2,
        reason: 'editing must not mutate the saved prototype');
    await state.saveChanges();
    await tester.pump();
    expect(completed, 0);
    expect(
        tester
            .widget<PopScope>(
                find.byWidgetPredicate((widget) => widget is PopScope).first)
            .canPop,
        isFalse);
    fail = false;
    final saving = state.saveChanges() as Future<void>;
    await tester.pump();
    expect(completed, 0);
    pending.complete();
    await saving;
    await tester.pump();
    expect(completed, 1);
    expect(
        tester
            .widget<PopScope>(
                find.byWidgetPredicate((widget) => widget is PopScope).first)
            .canPop,
        isTrue);
    expect(find.text(CommonStrings.discardChanges), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });
}
