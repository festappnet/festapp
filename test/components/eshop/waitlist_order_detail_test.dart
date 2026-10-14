import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/waitlist_order_detail.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:trina_grid/trina_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    Localization.load(
      const Locale('cs'),
      translations: Translations(
        jsonDecode(File('assets/translations/cs.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = null;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  Future<void> open(
    WidgetTester tester, {
    required String lifecycle,
    String? displayName,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaitlistOrderDetail(
            order: OrderModel(
              id: 5,
              orderSymbol: '9W6L1I6R4V',
              state: 'waitlisted',
            ),
            loadDetail: (id) async {
              expect(id, 5);
              loads++;
              return {
                'occasionTitle': 'Festival & letní setkání',
                'tickets': [
                  {
                    'id': 8837,
                    'displayName': displayName,
                    'lifecycle': lifecycle,
                    'ticket_symbol': null,
                    'waitlist_queue_at': null,
                    'created_at': null,
                    'updated_at': null,
                  },
                ],
                'capacity': {'serverTime': null},
                'offers': [],
                'linkedOrders': [],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Festival & letní setkání'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text(WaitlistStrings.offers), findsNothing);
    expect(find.text(WaitlistStrings.linkedOrders), findsNothing);
    expect(find.text(WaitlistStrings.text('adminWithdraw')), findsNothing);
    expect(find.text(WaitlistStrings.offerPlace), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('8837'), findsNothing);
    expect(find.textContaining('Osoba 1'), findsNothing);
  }

  testWidgets(
    'withdrawn single ticket shows safe display name and no empty sections or actions',
    (tester) async {
      await open(
        tester,
        lifecycle: 'withdrawn',
        displayName: 'Jana <Nováková>',
      );
      expect(find.text('Jana <Nováková>'), findsOneWidget);
      expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    },
  );

  testWidgets(
    'single readonly waiting ticket uses canonical application label',
    (tester) async {
      expect(RightsService.isEditorOrder(), isFalse);
      await open(tester, lifecycle: 'waiting');
      expect(find.text(OrdersStrings.itemSingular), findsOneWidget);
      expect(
          find.text(WaitlistStrings.text('waitingForPlace')), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    },
  );
  testWidgets(
    'withdraw command refreshes canonical detail and parent active grid',
    (tester) async {
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}),
      );
      var lifecycle = 'waiting';
      var gridLabel = '1 Čeká';
      var changes = 0;
      final mutations = <Map<String, dynamic>>[];
      final order = OrderModel(
        id: 5,
        state: 'waitlisted',
        orderSymbol: 'REGISTRATION',
      );
      late StateSetter parentState;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              parentState = setState;
              return Scaffold(
                body: Column(
                  children: [
                    Text(gridLabel, key: const Key('grid-summary')),
                    Expanded(
                      child: WaitlistOrderDetail(
                        order: order,
                        loadDetail: (_) async => {
                          'tickets': [
                            {
                              'id': 8837,
                              'displayName': 'Jana',
                              'lifecycle': lifecycle,
                            },
                          ],
                          'offers': [],
                          'linkedOrders': [],
                          'waitlistSummary': {
                            'counts': {lifecycle: 1},
                            'isActive': lifecycle == 'waiting',
                            'allowedActions': lifecycle == 'waiting'
                                ? ['view', 'withdraw', 'offer']
                                : ['view'],
                          },
                        },
                        executeCommand: (operation, payload) async {
                          mutations.add({'operation': operation, ...payload});
                          lifecycle = 'withdrawn';
                          return {'status': 'applied', 'code': 200};
                        },
                        onChanged: () async {
                          changes++;
                          parentState(() => gridLabel = '1 Vyřazen');
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(WaitlistStrings.withdrawTitle), findsOneWidget);
      expect(
        find.textContaining(WaitlistStrings.withdrawExplanation),
        findsOneWidget,
      );
      expect(find.text(WaitlistStrings.title), findsNothing);
      expect(mutations, isEmpty);
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.pumpAndSettle();
      expect(mutations, [
        {
          'operation': 'withdraw',
          'orderId': 5,
          'ticketIds': [8837],
        },
      ]);
      expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
      expect(changes, 1);
      expect(find.text('1 Čeká'), findsNothing);
      expect(find.text('1 Vyřazen'), findsOneWidget);
      expect(order.waitlistSummary!.counts, {'withdrawn': 1});
      expect(
        OrderGridFilters.orderIsActive(
          TrinaRow(
            cells: {
              EshopColumns.ORDER_MODEL_REFERENCE: TrinaCell(value: order),
            },
          ),
        ),
        isFalse,
      );
      expect(
        order.state,
        'waitlisted',
        reason: 'Client retains canonical order state and uses server activity',
      );
    },
  );

  Map<String, dynamic> waitingDetail({bool canSendOffers = true}) => {
        'tickets': [
          {'id': 8837, 'displayName': 'Jana', 'lifecycle': 'waiting'},
        ],
        'offers': [],
        'linkedOrders': [],
        'capacity': {'canSendOffers': canSendOffers},
      };
  void editor() =>
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}),
      );

  testWidgets(
    'cancelling withdrawal confirmation sends no mutation and keeps waiting',
    (tester) async {
      editor();
      var mutations = 0;
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaitlistOrderDetail(
              order: OrderModel(id: 5, state: 'waitlisted'),
              loadDetail: (_) async => waitingDetail(),
              executeCommand: (_, __) async {
                mutations++;
                return {};
              },
              onChanged: () async {
                refreshed++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(WaitlistStrings.withdrawExplanation),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
      await tester.pumpAndSettle();
      expect(mutations, 0);
      expect(refreshed, 0);
      expect(
          find.text(WaitlistStrings.text('waitingForPlace')), findsOneWidget);
    },
  );

  testWidgets('offer opens canonical preparation directly', (tester) async {
    editor();
    zones.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
    final form = FormModel(id: 7, waitlistEnabled: true);
    var opened = 0;
    var refreshed = 0;
    var offered = false;
    final order = OrderModel(id: 5, state: 'waitlisted', form: form);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaitlistOrderDetail(
            order: order,
            loadDetail: (_) async => offered
                ? {
                    ...waitingDetail(),
                    'tickets': [
                      {
                        'id': 1,
                        'displayName': 'Jana Nováková',
                        'lifecycle': 'offered'
                      }
                    ],
                    'offers': [
                      {
                        'id': 'offer-new',
                        'expires_at': '2030-01-02T12:00:00Z',
                        'slots': [
                          {'ticketId': 1, 'outcome': 'pending'}
                        ]
                      }
                    ],
                    'capacity': {'serverTime': '2030-01-01T12:00:00Z'},
                  }
                : waitingDetail(),
            onChanged: () async {
              refreshed++;
            },
            offerDialogBuilder: (selectedForm, orders) {
              expect(identical(selectedForm, form), isTrue);
              expect(orders.single.id, 5);
              opened++;
              return Builder(
                builder: (context) => AlertDialog(
                  title: const Text('Canonical offer review'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        offered = true;
                        Navigator.pop(context);
                      },
                      child: const Text('Close review'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final offerButton =
        find.widgetWithText(FilledButton, WaitlistStrings.offerPlace);
    final withdrawButton = find.widgetWithText(
        OutlinedButton, WaitlistStrings.text('adminWithdraw'));
    final participantCard = find
        .ancestor(
            of: offerButton,
            matching: find.byWidgetPredicate((widget) =>
                widget is Material && widget.shape is RoundedRectangleBorder))
        .first;
    expect(find.descendant(of: participantCard, matching: withdrawButton),
        findsOneWidget);
    expect(find.text(WaitlistStrings.refresh), findsNothing);
    expect(find.text(WaitlistStrings.text('adminWithdrawHelp')), findsNothing);
    await tester.tap(offerButton);
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.offerExplanation), findsNothing);
    expect(opened, 1);
    expect(find.text('Canonical offer review'), findsOneWidget);
    await tester.tap(find.text('Close review'));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(find.text(WaitlistStrings.text('awaitingOfferAcceptance')),
        findsOneWidget);
    expect(find.text(WaitlistStrings.offerPlace), findsNothing);
    expect(find.text(WaitlistStrings.text('activeOffer')), findsOneWidget);
    expect(find.text(WaitlistStrings.text('completeRegistration')),
        findsOneWidget);
    expect(find.text(WaitlistStrings.text('adminWithdraw')), findsOneWidget);
  });

  testWidgets(
    'server capacity denial disables offer without changing withdrawal eligibility',
    (tester) async {
      editor();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaitlistOrderDetail(
              order: OrderModel(
                id: 5,
                state: 'waitlisted',
                form: FormModel(id: 7, waitlistEnabled: true),
              ),
              loadDetail: (_) async => waitingDetail(canSendOffers: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, WaitlistStrings.offerPlace),
            )
            .onPressed,
        isNull,
      );
      expect(find.text(WaitlistStrings.full), findsOneWidget);
      expect(find.text(WaitlistStrings.text('recordDecline')), findsNothing);
      expect(find.text(WaitlistStrings.text('retractOffer')), findsNothing);
      expect(
        find.text(WaitlistStrings.text('adminWithdrawHelp')),
        findsNothing,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                WaitlistStrings.text('adminWithdraw'),
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'successful withdrawal stays completed when parent refresh fails',
    (tester) async {
      editor();
      var lifecycle = 'waiting';
      var mutations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaitlistOrderDetail(
              order: OrderModel(id: 5, state: 'waitlisted'),
              loadDetail: (_) async => {
                ...waitingDetail(),
                'tickets': [
                  {'id': 8837, 'lifecycle': lifecycle},
                ],
              },
              executeCommand: (_, __) async {
                mutations++;
                lifecycle = 'withdrawn';
                return {'code': 200};
              },
              onChanged: () async =>
                  throw StateError('read temporarily unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
      );
      await tester.pumpAndSettle();
      expect(mutations, 1);
      expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
      expect(find.text(WaitlistStrings.refreshAfterMutation), findsOneWidget);
      expect(find.text(WaitlistStrings.stale), findsNothing);
      expect(
        find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        ),
        findsNothing,
      );
    },
  );
  for (final count in [1, 2]) {
    testWidgets(
      'withdraws $count selected tickets across offers only after confirmation',
      (tester) async {
        editor();
        zones.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Europe/Prague'));
        tester.view.physicalSize = const Size(1000, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sent = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WaitlistOrderDetail(
                order: OrderModel(
                  id: 5,
                  state: 'waitlisted',
                  form: FormModel(id: 7, waitlistEnabled: true),
                ),
                loadDetail: (_) async => {
                  'tickets': [
                    for (var i = 1; i <= count; i++)
                      {
                        'id': i,
                        'displayName': 'Junák $i',
                        'lifecycle': 'offered',
                      },
                  ],
                  'offers': [
                    for (var i = 1; i <= count; i++)
                      {
                        'id': i == 1 ? 'offer-one' : 'offer-two',
                        'expires_at': '2030-01-02T12:00:00Z',
                        'slots': [
                          {'ticketId': i, 'outcome': 'pending'},
                        ],
                      },
                  ],
                  'capacity': {
                    'canSendOffers': false,
                    'serverTime': '2030-01-01T12:00:00Z',
                  },
                },
                executeCommand: (operation, payload) async {
                  sent.add({'operation': operation, ...payload});
                  return {'code': 200};
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(WaitlistStrings.full), findsNothing);
        expect(find.text(WaitlistStrings.offerPlace), findsNothing);
        expect(
          find.widgetWithText(
            FilledButton,
            WaitlistStrings.text('completeRegistration'),
          ),
          findsNWidgets(count),
        );
        final withdraw = find.widgetWithText(
          OutlinedButton,
          WaitlistStrings.text('adminWithdraw'),
        );
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(find.text(WaitlistStrings.text('recordDecline')), findsNothing);
        expect(find.text(WaitlistStrings.text('retractOffer')), findsNothing);
        if (count == 2) {
          expect(tester.widget<OutlinedButton>(withdraw).onPressed, isNull);
          expect(
            find.text(WaitlistStrings.text('withdrawSelection')),
            findsOneWidget,
          );
          for (var index = 0; index < count; index++) {
            final checkbox = find.byType(CheckboxListTile).at(index);
            await tester.ensureVisible(checkbox);
            await tester.tap(checkbox);
            await tester.pumpAndSettle();
          }
        } else {
          expect(find.byType(Checkbox), findsNothing);
        }
        expect(
          tester.widget<OutlinedButton>(withdraw).onPressed,
          isNotNull,
          reason: 'Withdrawal supports selected tickets from different offers',
        );
        await tester.ensureVisible(withdraw);
        await tester.tap(withdraw);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(WaitlistStrings.withdrawExplanation),
          findsOneWidget,
        );
        expect(sent, isEmpty);
        await tester.tap(
          find.widgetWithText(
            ElevatedButton,
            WaitlistStrings.text('adminWithdraw'),
          ),
        );
        await tester.pumpAndSettle();
        expect(sent.single, {
          'operation': 'withdraw',
          'orderId': 5,
          'ticketIds': [for (var i = 1; i <= count; i++) i],
        });
      },
    );
  }

  for (final size in [const Size(320, 760), const Size(1000, 800)]) {
    testWidgets('offer detail adapts to $size and opens a separate form', (
      tester,
    ) async {
      editor();
      zones.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Prague'));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opened = <String>[];
      var loads = 0;
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeConfig.theme(
              brightness: size.width > 500 ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: WaitlistOrderDetail(
                order: OrderModel(
                  id: 5,
                  state: 'waitlisted',
                  orderSymbol: '9W6L1I6R4V',
                ),
                openOfferForm: (id) async {
                  opened.add(id);
                },
                loadDetail: (_) async {
                  loads++;
                  return {
                    'occasionTitle': 'Festival & letní setkání',
                    'tickets': [
                      {
                        'id': 1,
                        'displayName': 'Jana Nováková',
                        'lifecycle': 'offered',
                      },
                    ],
                    'offers': [
                      {
                        'id': 'offer-one',
                        'expires_at': '2030-01-02T12:00:00Z',
                        'slots': [
                          {'ticketId': 1, 'outcome': 'pending'},
                        ],
                      },
                    ],
                    'capacity': {'serverTime': '2030-01-01T12:00:00Z'},
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(WaitlistStrings.text('adminWithdraw')), findsOneWidget);
      expect(find.text(WaitlistStrings.text('recordDecline')), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      final expiry = tester.widget<Text>(find.text('2. 1. 2030 13:00'));
      expect(expiry.maxLines, 1);
      expect(expiry.softWrap, isFalse);
      if (Platform.environment['WAITLIST_SCREENSHOTS'] == '1') {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/waitlist-single-withdraw-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(opened, ['offer-one']);
      expect(loads, 1, reason: 'Opening a new tab does not imply completion');
      expect(find.text(WaitlistStrings.refresh), findsNothing);
      expect(find.text(CommonStrings.retry), findsNothing);
      expect(find.text(WaitlistStrings.text('retractOffer')), findsNothing);
      expect(find.text(WaitlistStrings.text('recordDecline')), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(
        find.text(WaitlistStrings.text('adminWithdrawHelp')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.text(WaitlistStrings.text('adminWithdraw')),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('read-only pending offers never expose editor actions', (
    tester,
  ) async {
    zones.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaitlistOrderDetail(
            order: OrderModel(id: 5, state: 'waitlisted'),
            loadDetail: (_) async => {
              'tickets': [
                {'id': 1, 'displayName': 'Jana', 'lifecycle': 'offered'},
              ],
              'offers': [
                {
                  'id': 'offer-one',
                  'expires_at': '2030-01-02T12:00:00Z',
                  'slots': [
                    {'ticketId': 1, 'outcome': 'pending'},
                  ],
                },
              ],
              'capacity': {'serverTime': '2030-01-01T12:00:00Z'},
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.text('activeOffer')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text(WaitlistStrings.text('adminWithdraw')), findsNothing);
  });

  testWidgets('failed detail load can refresh into an explicit empty state', (
    tester,
  ) async {
    editor();
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaitlistOrderDetail(
            order: OrderModel(id: 5, state: 'waitlisted'),
            loadDetail: (_) async {
              if (loads++ == 0) throw StateError('offline');
              return {'tickets': [], 'offers': []};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.invalid), findsOneWidget);
    expect(find.text(WaitlistStrings.text('adminWithdraw')), findsNothing);
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.invalid), findsNothing);
    expect(find.text(WaitlistStrings.text('emptyDetail')), findsOneWidget);
  });
}
