import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
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
