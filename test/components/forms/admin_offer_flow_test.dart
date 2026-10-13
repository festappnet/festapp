import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/views/waitlist_order_detail.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/form_page.dart';
import 'package:fstapp/components/forms/views/order_preview_screen.dart';
import 'package:fstapp/components/forms/views/order_finish_screen.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as zones;

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync());
}

class _Navigation extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

void main() {
  testWidgets(
      'admin completes the real offer form without leaving administration or replacing rights context',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    zones.initializeTimeZones();
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = RightsService.occasionLinkModelNotifier.value;
    final admin = OccasionLinkModel(
        occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}));
    RightsService.occasionLinkModelNotifier.value = admin;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    final calls = <String>[];
    Map<String, dynamic>? accepted;
    final bundle = {
      'code': 200,
      'pendingCount': 1,
      'offerId': 'offer-1',
      'expiresAt': '2030-01-01T12:00:00Z',
      'slots': [
        {'ticketId': 101, 'outcome': 'pending'}
      ],
      'tickets': [
        {
          'id': 101,
          'lifecycle': 'offered',
          'answers': {
            'fields': [
              {'2': 'Junák'}
            ]
          }
        }
      ],
      'form': {
        'id': 7,
        'key': 'fixture',
        'secret': 'fixture-secret',
        'link': 'fixture',
        'is_open': true,
        'header': '<h1>PUBLIC DESCRIPTION</h1>',
        'fields': [
          {
            'id': 1,
            'type': 'ticket',
            'data': {'max_tickets': 1}
          },
          {
            'id': 2,
            'type': 'name',
            'title': 'Jméno',
            'is_ticket_field': true,
            'is_required': true
          },
          {'id': 3, 'type': 'email', 'title': 'E-mail', 'is_required': true},
          {
            'id': 4,
            'type': 'product_type',
            'title': 'Ubytování',
            'is_ticket_field': true,
            'is_required': true,
            'product_type_data': {
              'id': 4,
              'title': 'Ubytování',
              'type': 'select_one',
              'products': [
                {
                  'id': 9,
                  'title': 'Pokoj',
                  'price': 200,
                  'currency_code': 'CZK'
                }
              ]
            }
          },
        ],
      },
    };
    await tester.runAsync(() => Supabase.initialize(
          url: 'https://admin-offer.invalid',
          anonKey: 'fixture-anon',
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false, detectSessionInUri: false),
          httpClient: MockClient((request) async {
            calls.add(request.url.path);
            if (request.url.path.endsWith('/rpc/get_waitlist_offer_form')) {
              expect(jsonDecode(request.body)['p_offer_id'], 'offer-1');
              return http.Response(jsonEncode(bundle), 200,
                  headers: {'content-type': 'application/json'},
                  request: request);
            }
            if (request.url.path.endsWith('/functions/v1/send-ticket-order')) {
              accepted = Map<String, dynamic>.from(jsonDecode(request.body));
              return http.Response(
                  jsonEncode({
                    'status': 'applied',
                    'code': 200,
                    'mutation': {
                      'commandId': accepted!['commandId'],
                      'receiptId': accepted!['commandId'],
                      'commitId': null,
                      'replayed': false,
                      'occurredAt': '2026-10-13T12:00:00Z'
                    },
                    'sync': {'replacements': []},
                    'data': {
                      'code': 200,
                      'order': {
                        'order_symbol': 'CONFIRMED',
                        'data': {'email': 'test@example.invalid'}
                      }
                    }
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                  request: request);
            }
            throw StateError('Unexpected transport call ${request.url.path}');
          }),
        ));
    addTearDown(() => Supabase.instance.dispose());
    var loads = 0;
    var parentRefreshes = 0;
    final navigation = _Navigation();
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'unused',
      assetLoader: _Translations(),
      child: MaterialApp(
          navigatorObservers: [navigation],
          home: Scaffold(
              body: Builder(
                  builder: (context) => Column(children: [
                        const Text('ADMIN CONTEXT'),
                        TextButton(
                            onPressed: () => showDialog(
                                context: context,
                                builder: (_) => WaitlistOrderDetail(
                                      order: OrderModel(
                                          id: 5,
                                          state: 'waitlisted',
                                          orderSymbol: 'REGISTRATION',
                                          form: FormModel(
                                              id: 7,
                                              link: 'fixture',
                                              waitlistEnabled: true)),
                                      loadDetail: (_) async {
                                        loads++;
                                        return {
                                          'tickets': [
                                            {
                                              'id': 101,
                                              'displayName': 'Junák',
                                              'lifecycle': accepted == null
                                                  ? 'offered'
                                                  : 'admitted'
                                            }
                                          ],
                                          'capacity': {
                                            'serverTime': '2026-10-13T12:00:00Z'
                                          },
                                          'offers': [
                                            {
                                              'id': 'offer-1',
                                              'expires_at':
                                                  '2030-01-01T12:00:00Z',
                                              'slots': [
                                                {
                                                  'ticketId': 101,
                                                  'outcome': accepted == null
                                                      ? 'pending'
                                                      : 'accepted'
                                                }
                                              ]
                                            }
                                          ],
                                          'linkedOrders': []
                                        };
                                      },
                                      onChanged: () async => parentRefreshes++,
                                    )),
                            child: const Text('OPEN DETAIL')),
                      ])))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPEN DETAIL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(WaitlistStrings.text('completeRegistration')));
    await tester.pump();
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(FormPage), findsOneWidget);
    expect(find.text('PUBLIC DESCRIPTION'), findsNothing);
    expect(find.text('ADMIN CONTEXT'), findsOneWidget);
    expect(identical(RightsService.occasionLinkModelNotifier.value, admin),
        isTrue);
    final rootPushes = navigation.pushed.length;
    expect(find.byType(TextField), findsWidgets,
        reason:
            'Calls: $calls; visible: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}');
    final email = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.autofillHints?.contains(AutofillHints.email) == true);
    await tester.enterText(email, 'test@example.invalid');
    await tester.tap(find.textContaining('Pokoj').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(WaitlistStrings.accept));
    await tester.pumpAndSettle();
    expect(find.byType(OrderPreviewScreen), findsOneWidget,
        reason:
            'Visible: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}; fields: ${tester.widgetList<TextField>(find.byType(TextField)).map((field) => field.controller?.text).toList()}');
    final send = find.descendant(
        of: find.byType(OrderPreviewScreen),
        matching: find.byType(ElevatedButton));
    await tester.runAsync(() async {
      await tester.tap(send);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(FinishOrderScreen), findsOneWidget);
    expect(accepted, isNotNull, reason: 'Transport calls: $calls');
    expect(
        find.descendant(
            of: find.byType(FinishOrderScreen),
            matching: find.text(CommonStrings.back)),
        findsOneWidget);
    expect(accepted?['waitlistAcceptance']['ticketIds'], [101]);
    expect(accepted?['waitlistAcceptance']['offerId'], 'offer-1');
    expect(navigation.pushed.length, rootPushes);
    await tester.runAsync(() async {
      await tester.tap(find.descendant(
          of: find.byType(FinishOrderScreen),
          matching: find.text(CommonStrings.back)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(FormPage), findsNothing);
    expect(find.byType(WaitlistOrderDetail), findsOneWidget);
    expect(find.text('ADMIN CONTEXT'), findsOneWidget);
    expect(loads, 2);
    expect(parentRefreshes, 1);
    expect(identical(RightsService.occasionLinkModelNotifier.value, admin),
        isTrue);
    expect(
        calls
            .where((path) => path.endsWith('/rpc/get_waitlist_offer_form'))
            .length,
        1);
    expect(tester.takeException(), isNull);
  });
}
