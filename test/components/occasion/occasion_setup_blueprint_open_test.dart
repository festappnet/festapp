import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fstapp/components/occasion/setup/occasion_setup_page.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_demo.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  var textRequests = 0;
  const id = '10000000-0000-4000-8000-000000000001';
  setUpAll(() async {
    backend = await RootSupabaseFixture.open((request) {
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map;
      Object reply = <String, dynamic>{};
      if (request.url.path.endsWith('/get_occasion_setup_source_list'))
        reply = [];
      if (request.url.path.endsWith('/save_occasion_setup_draft')) {
        reply = {
          'id': id,
          'unit': 1,
          'revision': (body['p_expected_revision'] as int) + 1,
          'current_step': body['p_step'],
          'data': body['p_data']
        };
      }
      if (request.url.path
          .endsWith('/get_occasion_setup_blueprint_resources')) {
        reply = {
          'resources': {
            'protocol': 2,
            'fontFamilies': {},
            'textLayouts': {},
            'assets': {}
          }
        };
      }
      if (request.url.path.endsWith('/preview-ticket-layout')) {
        textRequests++;
        return http.Response(
            jsonEncode({
              'error':
                  'Ticket preview rejected. Check layout and image resources.'
            }),
            400,
            request: request,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(reply), 200,
          request: request, headers: {'content-type': 'application/json'});
    });
  });
  tearDownAll(() => backend.dispose());
  testWidgets(
      'selecting a hall template opens the draft without canonical text requests',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = OccasionSetupDraft.fromJson({
      'id': id,
      'unit': 1,
      'revision': 1,
      'current_step': 3,
      'data': {
        'title': 'Test event',
        'link': '',
        'start_time': '2026-11-01T10:00:00Z',
        'end_time': '2026-11-01T20:00:00Z',
        'start': '2026-11-01T10:00:00Z',
        'end': '2026-11-01T20:00:00Z',
        'storyQuestion': 'blueprint',
        'step': AppConfig.isAppSupported ? 4 : 6,
        'ticketFlowVersion': 4,
        'formEnabled': true,
        'formDefaultsInitialized': true,
        'appearance': {
          'id': 'clean',
          'primary': '4465A6',
          'secondary': '4465A6',
          'gradient': false,
          'fontFamily': 'Roboto'
        },
        'formDraft': {
          'title': 'Test event',
          'fields': [
            {'type': 'ticket'},
            {
              'type': 'product_type',
              'product_type_data': {
                'id': -1,
                'title': 'Admission',
                'type': 'spot',
                'products': [
                  {
                    'id': -2,
                    'title': 'Seat',
                    'price': 100,
                    'currency_code': 'CZK',
                    'is_hidden': false
                  }
                ]
              }
            }
          ]
        }
      }
    });
    await WidgetEnvironmentFixture(
            locale: const Locale('cs'),
            translations: jsonDecode(
                    File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>)
        .pumpWidget(
            tester,
            MaterialApp(
                localizationsDelegates:
                    VenueLayoutLocalizations.localizationsDelegates,
                supportedLocales: VenueLayoutLocalizations.supportedLocales,
                locale: const Locale('cs'),
                home: OccasionSetupPage(draft: draft)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vytvořit nový plánek'));
    await tester.pumpAndSettle();
    // Use the first populated template, independently of its catalog ID.
    final choices = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('layout-template-'));
    expect(choices, findsAtLeastNWidgets(2));
    await tester.tap(choices.at(1));
    for (var i = 0;
        i < 5 && find.byType(BlueprintLayoutDemo).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    expect(find.byType(BlueprintLayoutDemo), findsOneWidget,
        reason:
            '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList()} requests: ${backend.requests.map((r) => r.url.path).toList()}');
    expect(textRequests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
