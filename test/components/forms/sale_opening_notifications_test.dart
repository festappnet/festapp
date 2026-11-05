import 'dart:async';

import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:timezone/data/latest_all.dart' as timezones;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/sale_opening_settings.dart';
import 'package:fstapp/components/forms/widgets_view/presale_content.dart';
import 'package:fstapp/components/forms/widgets_view/sale_opening_notification.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  setUpAll(timezones.initializeTimeZones);
  WidgetEnvironmentFixture.register();
  final translations = jsonDecode(
    File('assets/translations/cs.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  WidgetEnvironmentFixture env() => WidgetEnvironmentFixture(
    locale: const Locale('cs'),
    translations: translations,
  );
  test('default off; schedule settings round trip without duplicating or moving existing slots', () {
    final form = FormDefinition.fromJson({
      'data': {
        'schedule': {
          'start_time': '2099-01-01T12:00:00Z',
          'enable_countdown': false,
        },
      },
    });
    expect(form.saleOpeningEnabled, isFalse);
    final configured = form
        .withSaleOpening(enabled: true)
        .withCountdownTitle(
          insertSaleOpeningBlock('<p>Intro</p>$countdownBlockHtml<p>End</p>'),
        );
    final html = configured.countdownTitle!;
    expect(
      html.indexOf('form-countdown'),
      lessThan(html.indexOf('form-sale-opening-notification')),
    );
    expect(insertSaleOpeningBlock(html), html);
    final reloaded = FormDefinition.fromJson(configured.toJson());
    expect(reloaded.saleOpeningEnabled, isTrue);
    expect(reloaded.enableCountdown, isFalse);
    expect(reloaded.countdownTitle, html);
  });
  testWidgets(
    'compact opt-in stacks centered full-width controls on mobile without surrounding copy',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SaleOpeningNotification(formLink: 'ples'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upozornit mě na začátek přihlašování'), findsOneWidget);
      expect(find.text('Upozornění na spuštění prodeje'), findsNothing);
      expect(
        find.text('Pošleme Vám e-mail, až se prodej spustí.'),
        findsNothing,
      );
      expect(
        find.text('Přihlášení nezajišťuje rezervaci ani přednostní nákup.'),
        findsNothing,
      );
      final field = tester.getRect(find.byType(TextField));
      final button = tester.getRect(find.byType(FilledButton));
      expect(button.top, greaterThan(field.bottom));
      expect(button.left, field.left);
      expect(button.width, field.width);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending opt-in blocks duplicates, then replaces controls with confirmation',
    (tester) async {
      final response = Completer<Map<String, dynamic>>();
      var calls = 0;
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SaleOpeningNotification(
              formLink: 'ples',
              command: (operation, payload) {
                calls++;
                expect(operation, 'subscribe');
                expect(payload['email'], 'jana@example.com');
                return response.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'jana@example.com');
      final submit = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Zpracovává se...'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      response.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(
        find.text(
          'Jakmile se otevře přihlašování, pošleme Vám zprávu na jana@example.com.',
        ),
        findsOneWidget,
      );
      submit();
      expect(calls, 1);
    },
  );
  testWidgets(
    'setting is unavailable without a future schedule, preview never offers a live submit',
    (tester) async {
      final form = FormEditorDraft(isOpen: true);
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SaleOpeningSettings(
              form: form,
              canEdit: true,
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zapnout upozornění'), findsNothing);
      expect(find.textContaining('budouc'), findsWidgets);
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: const Scaffold(
            body: SaleOpeningNotification(formLink: 'ples', preview: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      final preview = find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(IgnorePointer),
      );
      expect(
        preview.evaluate().any((e) => (e.widget as IgnorePointer).ignoring),
        isTrue,
      );
    },
  );
  testWidgets(
    'invalid email stays at its field without contacting the backend',
    (tester) async {
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: const Scaffold(body: SaleOpeningNotification(formLink: 'ples')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'invalid-address');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.errorText,
        isNotNull,
      );
    },
  );
  testWidgets(
    'enable and pause remain in the parent draft and preserve document order',
    (tester) async {
      final form = FormEditorDraft(
        isOpen: true,
        data: {
          'schedule': {
            'start_time': '2099-01-01T12:00:00Z',
            'enable_countdown': false,
            'countdown_title': '<p>Úvod</p>',
          },
        },
      );
      var changes = 0;
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SaleOpeningSettings(
                form: form,
                canEdit: true,
                onChanged: () {
                  changes++;
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapnout upozornění'));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningEnabled, isTrue);
      expect(
        form.definition.countdownTitle,
        contains('form-sale-opening-notification'),
      );
      final html = form.definition.countdownTitle;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningPaused, isTrue);
      expect(form.definition.countdownTitle, html);
      expect(form.toEditedJson()['settings']['sale_opening_notifications'], {
        'enabled': true,
        'collection_paused': true,
      });
      expect(changes, 2);
    },
  );
  testWidgets('subscription works without the timer or automatic date', (
    tester,
  ) async {
    await env().pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: PresaleContent(
            targetTime: DateTime.utc(2099, 1, 1, 12),
            onFinished: () {},
            showTimer: false,
            canSubscribe: true,
            formLink: 'ples',
            html: '$countdownBlockHtml$saleOpeningBlockHtml',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SaleOpeningNotification), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Upozornit mě na začátek přihlašování'), findsOneWidget);
    expect(find.textContaining('2099'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editor empty paragraphs keep the standalone opt-in vertically centered',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PresaleContent(
                targetTime: DateTime.utc(2099, 1, 1, 12),
                onFinished: () {},
                showTimer: false,
                canSubscribe: true,
                formLink: 'ples',
                html: '$saleOpeningBlockHtml<p><br></p>',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byType(TextField));
      final button = tester.getRect(find.byType(FilledButton));
      expect(field.top, greaterThan(200));
      expect(button.bottom, lessThan(600));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'paused subscription-only content shows the planned opening instead of an empty page',
    (tester) async {
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: PresaleContent(
              targetTime: DateTime.utc(2099, 1, 1, 12),
              onFinished: () {},
              showTimer: false,
              canSubscribe: false,
              html: '$saleOpeningBlockHtml<p><br></p>',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Přihlašování se otevře'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'resuming collection restores a removed slot without duplicating it',
    (tester) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.formsSaleOpeningSubscribersRead: true,
        },
      );
      addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = previous,
      );

      final form = FormEditorDraft(
        id: 1,
        isOpen: true,
        data: {
          'schedule': {
            'start_time': '2099-01-01T12:00:00Z',
            'countdown_title': '<p>Úvod</p>',
          },
          'sale_opening_notifications': {
            'enabled': true,
            'collection_paused': true,
          },
        },
      );
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SaleOpeningSettings(
                form: form,
                canEdit: true,
                loadSummary: (_) async => {
                  'phase': 'armed',
                  'subscribers': {'active': 7},
                },
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        find.textContaining('Dříve přihlášeným upozornění odejde.'),
        findsOneWidget,
      );
      expect(find.text('Přihlášení zájemci: 7'), findsNothing);
      expect(find.text('Příjemci upozornění (7)'), findsOneWidget);
      expect(find.text('Upravit e-maily'), findsNothing);
      expect(find.text('Ukončit upozornění'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningPaused, isFalse);
      expect(
        RegExp('form-sale-opening-notification')
            .allMatches(form.definition.countdownTitle!)
            .length,
        1,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    },
  );
  testWidgets(
    'pausing preserves delivery while permanent ending requires confirmation',
    (tester) async {
      final form = FormEditorDraft(
        id: 1,
        isOpen: true,
        data: {
          'schedule': {'start_time': '2099-01-01T12:00:00Z'},
          'sale_opening_notifications': {'enabled': true},
        },
      );
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SaleOpeningSettings(
                  form: form,
                  canEdit: true,
                  loadSummary: (_) async => {'phase': 'armed'},
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningEnabled, isTrue);
      expect(form.definition.saleOpeningPaused, isTrue);
      expect(find.text('Ukončit upozornění'), findsNothing);
      await tester.tap(find.text('Trvale ukončit upozornění'));
      await tester.pumpAndSettle();
      final end = find.widgetWithText(TextButton, 'Ukončit upozornění');
      await tester.ensureVisible(end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zrušit'));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningEnabled, isTrue);
      await tester.tap(end);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ukončit upozornění'));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningEnabled, isFalse);
      expect(
        find.text('Upozornění se ukončí po uložení formuláře.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'read-only and terminal states cannot change collection at narrow large-text sizes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final phase in ['armed', 'cancelled', 'completed']) {
        await env().pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SaleOpeningSettings(
                    form: FormEditorDraft(
                      id: 1,
                      isOpen: true,
                      data: {
                        'schedule': {'start_time': '2099-01-01T12:00:00Z'},
                        'sale_opening_notifications': {'enabled': true},
                      },
                    ),
                    canEdit: phase != 'armed',
                    loadSummary: (_) async => {
                      'phase': phase,
                      'subscribers': {'active': 0},
                    },
                    onChanged: () => fail('Collection must not change'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (phase == 'armed') {
          expect(
            tester
                .widget<SwitchListTile>(find.byType(SwitchListTile))
                .onChanged,
            isNull,
          );
        } else {
          expect(find.byType(SwitchListTile), findsNothing);
          expect(find.text('Zapnout upozornění'), findsNothing);
        }
        expect(find.text('Trvale ukončit upozornění'), findsNothing);
        expect(find.text('Příjemci upozornění: 0'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'availability menu focuses the presale section and activation uses the parent draft',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.formsWrite: true,
          AuthorizationCapabilities.ordersRead: true,
        },
      );
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final form = FormEditorDraft(
        link: 'ples',
        title: 'Podzimní ples',
        isOpen: true,
        data: {
          'schedule': {'start_time': '2099-01-01T12:00:00Z'},
        },
      );
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormEditorContent(
            formLink: 'ples',
            loadBundle: (_) async => FormEditBundle(
              form: form,
              productTypes: [],
              products: [],
              availableBankAccounts: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zapnout upozornění'), findsNothing);
      final menu = find.byKey(const ValueKey('form-availability-menu'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upozornění na začátek přihlašování'));
      await tester.pumpAndSettle();
      expect(find.text('Stránka před otevřením'), findsOneWidget);
      expect(find.text('Použít změny'), findsNothing);
      expect(form.definition.saleOpeningEnabled, isFalse);
      await tester.ensureVisible(find.text('Zapnout upozornění'));
      await tester.tap(find.text('Zapnout upozornění'));
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningEnabled, isTrue);
      expect(
        form.definition.presaleContent,
        contains('form-sale-opening-notification'),
      );
      expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isTrue,
      );
      expect(find.text('Standardní hlavička'), findsNothing);
      expect(find.text('Použít změny'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing or past start does not claim notifications are processing',
    (tester) async {
      for (final start in [null, '2000-01-01T12:00:00Z']) {
        final form = FormEditorDraft(
          isOpen: true,
          data: {
            'sale_opening_notifications': {'enabled': true},
            'schedule': {'start_time': start},
          },
        );
        await env().pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: SaleOpeningSettings(
                form: form,
                canEdit: true,
                onChanged: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Upozornění se zpracovávají'), findsNothing);
        if (start == null) {
          expect(
            find.text('Nastavte budoucí začátek a otevřete formulář.'),
            findsWidgets,
          );
        } else {
          expect(
            find.text('Čekáme na skutečné otevření přihlašování.'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'summary failure offers retry instead of misleading zero subscribers',
    (tester) async {
      var reads = 0;
      final form = FormEditorDraft(
        id: 1,
        isOpen: true,
        data: {
          'schedule': {'start_time': '2099-01-01T12:00:00Z'},
        },
      );
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SaleOpeningSettings(
              form: form,
              canEdit: true,
              onChanged: () {},
              loadSummary: (_) async {
                reads++;
                if (reads == 1) throw StateError('offline');
                return {'phase': 'armed'};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Stav upozornění se nepodařilo načíst.'),
        findsOneWidget,
      );
      expect(find.text('Příjemci upozornění: 0'), findsNothing);
      await tester.tap(find.text('Zkusit znovu'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Zapnout upozornění'), findsOneWidget);
    },
  );
}
