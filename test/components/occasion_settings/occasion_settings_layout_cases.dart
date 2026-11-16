import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/features/deposit_feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_layout.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/occasion_settings_fixture.dart';
import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
    await TimeHelper.initializeTimeZone();
  });

  testWidgetsWithEnvironment(
    () => environment,
    'real page public save validates hidden enabled editor then writes exactly once',
    (tester) async {
      final rights = RightsContextFixture();
      addTearDown(rights.dispose);
      final fixture = OccasionSettingsFixture();
      fixture.saved.features.add(
        DepositFeature(
          code: FeatureConstants.deposit,
          isEnabled: true,
          depositDeadlineDays: -1,
        ),
      );
      fixture.installRights();
      final router = OccasionSettingsFixtureRouter(fixture);
      addTearDown(router.dispose);
      await environment.pumpWidget(
        tester,
        MaterialApp.router(
          builder: DependencyMaterialBridge.builder,
          routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/ples-u-lipy/settings'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(fixture.saves, 0);
      final invalid = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '-1',
      );
      expect(invalid, findsOneWidget);
      await tester.enterText(invalid, '7');
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isTrue,
      );
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(fixture.saves, 1);
      expect(fixture.refreshes, 1);
      expect(
        fixture.saved.features
            .whereType<DepositFeature>()
            .first
            .depositDeadlineDays,
        7,
      );
      expect(fixture.ticketSaves, 0);
      final ticket = tester.widget<TicketSettings>(
        find.byType(TicketSettings, skipOffstage: false),
      );
      await ticket.onSave!(TicketFeature.fromJson(ticket.feature.toJson()));
      expect(fixture.ticketSaves, 1);
      expect(fixture.saves, 1);
      final editedField = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '7',
      );
      final beforeDiscard = tester.state(editedField);
      await tester.enterText(editedField, '12');
      await tester.pumpAndSettle();
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onDiscard();
      await tester.pumpAndSettle();
      final restored = find.descendant(
        of: find.byKey(
          const ValueKey('feature-host-deposit'),
          skipOffstage: false,
        ),
        matching: find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == '7',
          skipOffstage: false,
        ),
        skipOffstage: false,
      );
      expect(restored, findsOneWidget);
      expect(tester.state(restored), isNot(same(beforeDiscard)));
      expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'details stay compact and active HTML draft survives desktop mobile resize and save',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rights = RightsContextFixture();
      addTearDown(rights.dispose);
      final fixture = OccasionSettingsFixture()..installRights();
      final router = OccasionSettingsFixtureRouter(fixture);
      addTearDown(router.dispose);
      await environment.pumpWidget(
        tester,
        MaterialApp.router(
          builder: DependencyMaterialBridge.builder,
          routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/ples-u-lipy/settings'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (w) => w is TextFormField && w.initialValue == fixture.saved.title,
      );
      expect(tester.getSize(title).width, lessThanOrEqualTo(720));
      final layout = tester
          .widget<OccasionSettingsLayout>(find.byType(OccasionSettingsLayout))
          .controller;
      layout.reveal(OccasionSettingsChapter.appearance);
      await tester.pumpAndSettle();
      final htmlField = find.byType(EditableHtmlField);
      final edit = find.descendant(
        of: htmlField,
        matching: find.byIcon(Icons.edit),
      );
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<RichHtmlEditor>(find.byType(RichHtmlEditor))
          .controller;
      controller.appendHtml('<p>Rozepsaná pozvánka na ples.</p>');
      await tester.pumpAndSettle();
      for (final width in [390.0, 820.0, 1300.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        final current = tester.widget<RichHtmlEditor>(
          find.byType(RichHtmlEditor),
        );
        expect(current.controller, same(controller));
        expect(
          current.controller.html,
          contains('Rozepsaná pozvánka na ples.'),
        );
      }
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(fixture.saves, 1);
      expect(
        fixture.saved.description,
        contains('Rozepsaná pozvánka na ples.'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'mobile chapters preserve field identity and large text keeps actions reachable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = OccasionSettingsLayoutController();
      addTearDown(controller.dispose);
      final fieldController = TextEditingController(text: 'Ples');
      addTearDown(fieldController.dispose);
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: OccasionSettingsLayout(
                      controller: controller,
                      details: TextField(controller: fieldController),
                      appearance: const Text('Obrázek a popis'),
                      features: const Text('Funkce akce'),
                      advanced: const Text('Pokročilé údaje'),
                    ),
                  ),
                  EditorActionBar(
                    hasChanges: true,
                    onSave: () async {},
                    onDiscard: () async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = tester.state(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Rozepsaný ples');
      controller.toggle(OccasionSettingsChapter.details);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      controller.toggle(OccasionSettingsChapter.details);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(original));
      expect(fieldController.text, 'Rozepsaný ples');
      final bar = tester.getRect(find.byType(EditorActionBar));
      expect(bar.bottom, lessThanOrEqualTo(844));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'chapter reveal never moves enclosing horizontal PageView during animation',
    (tester) async {
      final page = PageController();
      final layout = OccasionSettingsLayoutController();
      addTearDown(page.dispose);
      addTearDown(layout.dispose);
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: PageView(
              controller: page,
              children: [
                OccasionSettingsLayout(
                  controller: layout,
                  details: const SizedBox(height: 1000),
                  appearance: const SizedBox(height: 1000),
                  features: const SizedBox(height: 1000),
                  advanced: const Text('Odkaz akce'),
                ),
                const Text('Jiná karta'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      layout.reveal(OccasionSettingsChapter.advanced);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(page.offset, 0);
      }
      expect(layout.scrollController.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
}
