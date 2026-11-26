import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:festapp_core/time.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/widgets_editor/ticket_product_editor_row.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_presentation.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_review_row.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story_shell.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_bank_account.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_page.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  Map<String, dynamic>? saved;
  const id = '10000000-0000-4000-8000-000000000001';

  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    backend = await RootSupabaseFixture.open((request) {
      final Object reply;
      switch (request.url.pathSegments.last) {
        case 'get_occasion_setup_source_list':
          reply = [];
        case 'get_occasion_setup_bank_accounts':
          reply = {'canManage': true, 'accounts': []};
        case 'save_occasion_setup_draft':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          saved = body['p_data'] as Map<String, dynamic>;
          reply = {
            'id': id,
            'unit': 1,
            'revision': (body['p_expected_revision'] as int) + 1,
            'current_step': body['p_step'],
            'data': saved,
          };
        default:
          reply = <String, dynamic>{};
      }
      return http.Response(
        jsonEncode(reply),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
  });
  tearDownAll(() => backend.dispose());

  OccasionSetupDraft draftAt(String question, int step) =>
      OccasionSetupDraft.fromJson({
        'id': id,
        'unit': 1,
        'revision': 1,
        'current_step': step,
        'data': {
          'title': 'Jarní ples',
          'start_time': '2027-03-06T18:00:00Z',
          'end_time': '2027-03-07T01:00:00Z',
          'storyQuestion': question,
          'step': step,
          'saleMode': 'immediate',
          'isPromoted': AppConfig.isAppSupported,
          'reviewConfirmed': true,
          'formDefaultsInitialized': true,
          'formDraft': {
            'title': 'Jarní ples',
            'fields': [
              {'type': 'email', 'title': 'E-mail', 'order': 0},
              {
                'type': 'ticket',
                'title': 'Vstupenka',
                'order': 2,
                'is_ticket_field': true,
              },
              {
                'type': 'product_type',
                'is_ticket_field': true,
                'title': 'Vstupné',
                'order': 1,
                'product_type_data': {
                  'id': -1,
                  'type': 'spot',
                  'title': 'Vstupné',
                  'products': [
                    {
                      'id': -2,
                      'title': 'Základní',
                      'price': 0,
                      'currency_code': 'CZK',
                    },
                  ],
                },
              },
            ],
          },
        },
      });

  Future<void> pumpDraft(WidgetTester tester, OccasionSetupDraft draft) =>
      WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('cs')],
          locale: const Locale('cs'),
          home: OccasionSetupPage(draft: draft),
        ),
      );

  void useWideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('public catalogue requires a cover only for an event it will list', () {
    for (final saleMode in ['preparation', 'immediate', 'scheduled']) {
      for (final listPublicly in [false, true]) {
        final data = <String, dynamic>{
          'introImage': '  ',
          'saleMode': saleMode,
          'listPubliclyOnPublish': listPublicly,
        };
        expect(
          occasionSetupCoverIssue(data, appSupported: false),
          listPublicly && saleMode != 'preparation'
              ? 'listingImageRequired'
              : null,
        );
        data['formEnabled'] = false;
        expect(occasionSetupCoverIssue(data, appSupported: false), isNull);
      }
    }
  });

  testWidgets('review blocks completion and opens the cover upload step', (
    tester,
  ) async {
    useWideViewport(tester);
    await pumpDraft(tester, draftAt('review', 5));
    final row = find.widgetWithText(
      OccasionSetupReviewRow,
      'Chybí povinný obrázek',
    );
    expect(tester.widget<OccasionSetupReviewRow>(row).hasError, isTrue);
    final shell = tester.widget<OccasionSetupStoryShell>(
      find.byType(OccasionSetupStoryShell),
    );
    expect((shell.primaryAction as FilledButton).onPressed, isNull);

    final warning = find.text(
      AppConfig.isAppSupported
          ? 'Pro propagaci události je nutný úvodní obrázek.'
          : 'Pro zveřejnění akce v katalogu nahrajte úvodní obrázek.',
    );
    await tester.ensureVisible(warning);
    await tester.tap(warning);
    await tester.pumpAndSettle();
    expect(find.byType(ImageArea), findsOneWidget);
    expect(saved?['storyQuestion'], 'promotion');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new product edits survive saving and reopening the wizard draft',
    (tester) async {
      useWideViewport(tester);
      await pumpDraft(tester, draftAt('form', 3));
      await tester.pumpAndSettle();
      final addProduct = find.text(FormStrings.addProduct);
      await tester.ensureVisible(addProduct);
      await tester.tap(addProduct);
      await tester.pumpAndSettle();

      final product = find.byType(TicketProductEditorRow).last;
      final inputs = find.descendant(
        of: product,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(inputs.first);
      await tester.enterText(inputs.first, 'Balkon');
      await tester.enterText(inputs.at(1), '275,50');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final stored = saved!;
      final fields = stored['formDraft']['fields'] as List;
      final type = fields.singleWhere(
        (field) => field['type'] == 'product_type',
      )['product_type_data'];
      final variant = (type['products'] as List).singleWhere(
        (p) => p['title'] == 'Balkon',
      );
      expect(variant['price'], 275.5);
      expect(variant['currency_code'], 'CZK');
      final productId = variant['id'] as int;
      expect(productId, isNegative);
      expect(variant['product_type'], type['id']);

      await tester.pumpWidget(const SizedBox());
      await pumpDraft(
        tester,
        OccasionSetupDraft.fromJson({
          'id': id,
          'unit': 1,
          'revision': 10,
          'current_step': 3,
          'data': stored,
        }),
      );
      await tester.pumpAndSettle();
      final restored = tester
          .widget<TicketProductEditorRow>(
            find.byType(TicketProductEditorRow).last,
          )
          .product;
      expect(restored.id, productId);
      expect(restored.title, 'Balkon');
      expect(restored.price, 275.5);
      expect(restored.currencyCode, 'CZK');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('selecting bank transfer enables it and saves the choice', (
    tester,
  ) async {
    final previous = RightsService.occasionLinkModelNotifier.value;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      unit: UnitModel(
        id: 1,
        paymentMethodPolicy: {
          'methods': {
            'bank': {'policyEnabled': true},
          },
        },
      ),
    );
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final step = AppConfig.isAppSupported ? 3 : 4;
    final draft = OccasionSetupDraft.fromJson({
      'id': id,
      'unit': 1,
      'revision': 1,
      'current_step': step,
      'data': {
        'title': 'Jarní ples',
        'link': '',
        'start_time': '2027-03-06T18:00:00Z',
        'end_time': '2027-03-07T01:00:00Z',
        'storyQuestion': 'payments',
        'step': step,
        'formDefaultsInitialized': true,
        'payments': {'bankEnabled': false},
        'formDraft': {
          'title': 'Jarní ples',
          'fields': [
            {
              'type': 'product_type',
              'product_type_data': {
                'type': 'spot',
                'products': [
                  {'id': -1, 'title': 'Základní', 'price': 350},
                ],
              },
            },
          ],
        },
      },
    });
    await WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    ).pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('cs')],
        locale: const Locale('cs'),
        home: OccasionSetupPage(draft: draft),
      ),
    );

    expect(find.byType(OccasionSetupBankAccount), findsNothing);
    await tester.tap(find.byKey(const ValueKey('payment-method-bank')));
    await tester.pump();
    expect(find.byType(OccasionSetupBankAccount), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(saved?['payments'], containsPair('bankEnabled', true));
  });
}
