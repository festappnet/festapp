import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/sale_opening_settings.dart';
import 'package:fstapp/components/forms/widgets_view/countdown_content.dart';
import 'package:fstapp/components/forms/widgets_view/sale_opening_notification.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
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
    'compact opt-in keeps email and short button on one mobile row without surrounding copy',
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
      expect(button.top, field.top);
      expect(button.left, greaterThan(field.right));
      expect(tester.takeException(), isNull);
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
      expect(
        tester
            .widget<SwitchListTile>(find.byType(SwitchListTile).first)
            .onChanged,
        isNull,
      );
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
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
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
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(form.definition.saleOpeningEnabled, isTrue);
      expect(
        form.definition.countdownTitle,
        contains('form-sale-opening-notification'),
      );
      final html = form.definition.countdownTitle;
      await tester.tap(find.byType(SwitchListTile).at(1));
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
          body: CountdownContent(
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
}
