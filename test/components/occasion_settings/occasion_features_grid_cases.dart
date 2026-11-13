import 'dart:ui' show SemanticsAction;

import 'package:flutter/services.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/features/deposit_feature.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_metadata.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/features/deposit_feature.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/occasion_settings/occasion_features_controller.dart';
import 'package:fstapp/components/occasion_settings/occasion_features_section.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(
    () => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    ),
  );

  testWidgetsWithEnvironment(
    () => environment,
    'card switch changes draft and tile modal retains invalid input across close',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = OccasionFeaturesController();
        final feature = DepositFeature(
          code: FeatureConstants.deposit,
          isEnabled: false,
          depositDeadlineDays: 7,
        );
        var dirty = 0;
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: SingleChildScrollView(
                child: EditorDraftScope(
                  onChanged: () {
                    controller.save();
                    dirty++;
                  },
                  child: OccasionFeaturesSection(
                    features: [feature],
                    isEditingEnabled: true,
                    occasionId: 991,
                    controller: controller,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        await tester.tap(find.byKey(const ValueKey('toggle-deposit')));
        await tester.pumpAndSettle();
        expect(feature.isEnabled, isTrue);
        expect(dirty, greaterThan(0));
        expect(find.byType(AppDialog), findsNothing);
        final toggle = tester.getSemantics(
          find.byKey(const ValueKey('toggle-deposit')),
        );
        expect(toggle.rect.width, lessThanOrEqualTo(80));
        final card = tester.getSemantics(
          find.byKey(const ValueKey('feature-action-deposit')),
        );
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          card.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(feature.isEnabled, isTrue);
        expect(find.byType(AppDialog), findsOneWidget);
        final field = find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == '7',
        );
        final state = tester.state(field);
        await tester.enterText(field, '-1');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        final errors = controller.validateGranularly();
        expect(errors, hasLength(1));
        controller.reveal(
          feature.code,
          target: errors.single.fields.first.context,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsOneWidget);
        final invalid = find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == '-1',
        );
        expect(tester.state(invalid), same(state));
        await tester.enterText(invalid, '9');
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(AppDialog))).maybePop();
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        expect(feature.depositDeadlineDays, 9);
        expect(controller.validateGranularly(), isEmpty);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'persistent onSaved editor survives close search regroup and 3 2 1 columns',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = OccasionFeaturesController();
      final feature = FormFeature(
        code: FeatureConstants.form,
        isEnabled: true,
        reserveButtonTitle: 'Rezervovat',
        reminderIsEnabled: true,
        deadlineDurationSeconds: 604800,
        reminderIntervalSeconds: 86400,
      );
      var dirty = 0;
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: EditorDraftScope(
                onChanged: () {
                  controller.save();
                  dirty++;
                },
                child: OccasionFeaturesSection(
                  features: [
                    feature,
                    SimpleFeature(
                      code: FeatureConstants.songbook,
                      isEnabled: true,
                    ),
                    SimpleFeature(code: FeatureConstants.game, isEnabled: true),
                  ],
                  isEditingEnabled: true,
                  occasionId: 991,
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialDirty = dirty;
      await tester.tap(find.byKey(const ValueKey('configure-form')));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      expect(dirty, initialDirty);
      await tester.ensureVisible(find.text(FormStrings.labelAdvancedSettings));
      await tester.tap(find.text(FormStrings.labelAdvancedSettings));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Rezervovat',
      );
      expect(title, findsOneWidget);
      final state = tester.state(title);
      await tester.enterText(title, 'Koupit vstupenky');
      await tester.pump();
      expect(feature.reserveButtonTitle, 'Koupit vstupenky');
      expect(dirty, greaterThan(initialDirty));
      final editedDirty = dirty;
      for (final width in [800.0, 390.0, 1300.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpAndSettle();
        final field = find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == 'Koupit vstupenky',
        );
        expect(tester.state(field), same(state));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'neexistující funkce',
      );
      await tester.pumpAndSettle();
      expect(controller.validateGranularly(), isEmpty);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      controller.reveal(FeatureConstants.form);
      await tester.pumpAndSettle();
      expect(
        tester.state(
          find.byWidgetPredicate(
            (w) =>
                w is TextFormField && w.controller?.text == 'Koupit vstupenky',
          ),
        ),
        same(state),
      );
      expect(dirty, editedDirty);
      if (AppConfig.isAppSupported) {
        await tester.tap(find.byType(SwitchListTile).first);
        await tester.pumpAndSettle();
        expect(feature.isEnabled, isFalse);
        expect(feature.reserveButtonTitle, 'Koupit vstupenky');
        expect(
          tester.state(
            find.byWidgetPredicate(
              (w) =>
                  w is TextFormField &&
                  w.controller?.text == 'Koupit vstupenky',
            ),
          ),
          same(state),
        );
      }
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'feature grid uses three two one columns and large text stays within width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [1300.0, 800.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: SingleChildScrollView(
                child: OccasionFeaturesSection(
                  key: ValueKey(width),
                  features: [
                    SimpleFeature(code: FeatureConstants.form, isEnabled: true),
                    SimpleFeature(
                      code: FeatureConstants.ticket,
                      isEnabled: true,
                    ),
                    SimpleFeature(
                      code: FeatureConstants.deposit,
                      isEnabled: true,
                    ),
                    SimpleFeature(
                      code: FeatureConstants.blueprint,
                      isEnabled: false,
                    ),
                  ],
                  isEditingEnabled: true,
                  occasionId: 0,
                  controller: OccasionFeaturesController(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final a = tester.getRect(find.byKey(const ValueKey('configure-form')));
        final b = tester.getRect(
          find.byKey(const ValueKey('configure-ticket')),
        );
        final c = tester.getRect(
          find.byKey(const ValueKey('configure-deposit')),
        );
        final tileSizes = [
          for (final code in ['form', 'ticket', 'deposit', 'blueprint'])
            tester.getSize(find.byKey(ValueKey('feature-tile-$code'))),
        ];
        for (final size in tileSizes.skip(1)) {
          expect(size.width, closeTo(tileSizes.first.width, .01));
          expect(size.height, closeTo(tileSizes.first.height, .01));
        }
        if (width >= 900) {
          expect(a.left, lessThan(b.left));
          expect(b.left, lessThan(c.left));
        } else if (width >= 600) {
          expect(a.left, lessThan(b.left));
          expect(c.top, greaterThan(a.top));
        } else {
          expect(b.top, greaterThan(a.top));
          expect(c.top, greaterThan(b.top));
        }
        expect(tester.takeException(), isNull);
      }
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 1100),
                textScaler: TextScaler.linear(2),
              ),
              child: SingleChildScrollView(
                child: OccasionFeaturesSection(
                  features: [
                    SimpleFeature(code: FeatureConstants.form, isEnabled: true),
                    SimpleFeature(code: FeatureConstants.deposit),
                  ],
                  isEditingEnabled: true,
                  occasionId: 0,
                  controller: OccasionFeaturesController(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('configure-form'))).right,
        lessThanOrEqualTo(390),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'enabled hidden validation blocks while disabled visited validation does not',
    (tester) async {
      final controller = OccasionFeaturesController();
      final feature = DepositFeature(
        code: FeatureConstants.deposit,
        isEnabled: true,
        depositDeadlineDays: -1,
      );
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: OccasionFeaturesSection(
                features: [feature],
                isEditingEnabled: true,
                occasionId: 991,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        controller.validateGranularly().single.code,
        FeatureConstants.deposit,
      );
      if (AppConfig.isAppSupported) {
        feature.isEnabled = false;
        expect(controller.validateGranularly(), isEmpty);
      } else {
        feature.isEnabled = false;
        expect(controller.validateGranularly(), isEmpty);
      }
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'read only can configure but cannot toggle or edit and unsupported projection is filtered',
    (tester) async {
      final feature = FormFeature(code: FeatureConstants.form, isEnabled: true);
      final editable = ValueNotifier(false);
      addTearDown(editable.dispose);
      final controller = OccasionFeaturesController();
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<bool>(
                valueListenable: editable,
                builder: (_, canEdit, _) => OccasionFeaturesSection(
                  features: [
                    feature,
                    SimpleFeature(
                      code: FeatureConstants.songbook,
                      isEnabled: false,
                    ),
                  ],
                  isEditingEnabled: canEdit,
                  occasionId: 991,
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(FeatureMetadata.getTitle(FeatureConstants.songbook)),
        AppConfig.isAppSupported ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('toggle-form')))
            .onChanged,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('configure-form')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byType(SwitchListTile).first)
            .onChanged,
        isNull,
      );
      editable.value = true;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byType(SwitchListTile).first)
            .onChanged,
        AppConfig.isAppSupported ? isNotNull : isNull,
      );
      editable.value = false;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byType(SwitchListTile).first)
            .onChanged,
        isNull,
      );
      expect(feature.isEnabled, isTrue);
    },
  );
}
