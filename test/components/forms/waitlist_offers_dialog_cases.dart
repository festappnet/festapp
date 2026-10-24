import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:fstapp/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:fstapp/components/forms/views/waitlist_offers_dialog.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/waitlist_summary_model.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
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
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
    if (!tz.timeZoneDatabase.isInitialized) {
      zones.initializeTimeZones();
    }
    final previousZone = tz.local;
    addTearDown(() => tz.setLocalLocation(previousZone));
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  });
  for (final count in [1, 2, 5]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'focused offer sends only selected registration and expands inherited preview for$count',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final form = FormBundle(
            definition: FormDefinition(id: 7, waitlistEnabled: true));
        final selected = OrderModel(
          id: 5,
          formId: 7,
          state: 'waitlisted',
          orderSymbol: 'SELECTED5',
          data: {'name': 'Jana Nováková', 'email': 'jana@example.invalid'},
        );
        selected.waitlistSummary = WaitlistSummaryModel.fromJson({
          'counts': {'waiting': count},
        });
        final other = OrderModel(
          id: 6,
          formId: 7,
          state: 'waitlisted',
          orderSymbol: 'OTHER6',
        );
        final sent = <Map<String, dynamic>>[];
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => WaitlistOffersDialog(
                      form: form,
                      orders: [selected, other],
                      targetOrderId: 5,
                      loadProposal: (id) async {
                        expect(id, 7);
                        return {
                          'revision': 77,
                          'serverTime': '2026-03-29T00:30:00Z',
                          'offerDurationSeconds': 3600,
                          'capacity': {
                            'enabled': true,
                            'canSendOffers': true,
                            'offerablePlaces': count + 1,
                          },
                          'recipients': [
                            {
                              'orderId': 5,
                              'count': count,
                              'waitingCount': count,
                            },
                            {'orderId': 6, 'count': 1, 'waitingCount': 1},
                          ],
                        };
                      },
                      loadPreview: (id) async => {
                        'occasionTitle': 'Festival <test>',
                        'toneSubstitutions': {
                          'waitlist_offer_button_single': 'Potvrdit přihlášení',
                          'waitlist_offer_button_multiple':
                              'Potvrdit vybrané osoby',
                          'waitlist_manage_button_label': 'Spravovat čekání',
                          'waitlist_offer_heading': count == 2
                              ? 'Máme pro tebe nabídku'
                              : 'Máme pro vás nabídku',
                          'waitlist_offer_instructions_single':
                              'Doplňte údaje a potvrďte přihlášení.',
                          'waitlist_offer_instructions': count == 2
                              ? 'Objednávku pak potvrdíš.'
                              : 'Objednávku pak potvrdíte.',
                        },
                        'instructionsTemplateHtml':
                            '<h2>{{waitlist_offer_heading}}</h2><p>{{waitlist_offer_instructions}}</p><p>{{participant_phrase}} | {{participant_count}} | {{offered_count}} | <span style="white-space:nowrap">{{offer_expires_at}}</span></p><p>{{occasion_title}}</p>{{offer_button}}',
                        'template': {
                          'subject': 'Nabídka pro {{offered_places}}',
                          'html':
                              '<h2>{{waitlist_offer_heading}}</h2><p>Legacy expanded multi-person instructions.</p><p>{{participant_phrase}} | {{participant_count}} | {{offered_count}} | <span style="white-space:nowrap">{{offer_expires_at}}</span></p><p>{{occasion_title}}</p>{{offer_button}}',
                        },
                        'wrapper': {'html': '<main>{{content}}</main>'},
                      },
                      executeCommand: (operation, payload) async {
                        sent.add({'operation': operation, ...payload});
                        return {'code': 200};
                      },
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Jana Nováková'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('offer-increase-5')),
          count == 1 ? findsNothing : findsOneWidget,
        );
        expect(find.textContaining('OTHER6'), findsNothing);
        expect(
          find.text(WaitlistStrings.offerReviewExplanation),
          findsOneWidget,
        );
        expect(find.byType(ExpansionTile), findsNothing);
        final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
        final people = count == 1
            ? '1 osobu'
            : count == 2
                ? '2 osoby'
                : '5 osob';
        final places = count == 1
            ? '1 místo'
            : count == 2
                ? '2 místa'
                : '5 míst';
        expect(
          html,
          contains(
            count == 2 ? 'Máme pro tebe nabídku' : 'Máme pro vás nabídku',
          ),
        );
        expect(
          html,
          contains(
            count == 1
                ? 'Doplňte údaje a potvrďte přihlášení.'
                : count == 2
                    ? 'Objednávku pak potvrdíš.'
                    : 'Objednávku pak potvrdíte.',
          ),
        );
        expect(
          html,
          contains(
            count == 1 ? 'Potvrdit přihlášení' : 'Potvrdit vybrané osoby',
          ),
        );
        expect(html, contains(people));
        expect(html, contains(places));
        expect(html.replaceAll('\u00a0', ' '), contains('29. 3. 2026 3:30'));
        expect(html, contains('white-space:nowrap'));
        expect(html, contains('29.\u00a03.\u00a02026\u00a03:30'));
        expect(html, contains('Festival &lt;test&gt;'));
        expect(html, isNot(contains('Europe')));
        expect(html, isNot(contains('UTC')));
        expect(html, isNot(contains('{{')));
        if (count == 2) {
          await tester.tap(find.byKey(const ValueKey('offer-decrease-5')));
          await tester.pumpAndSettle();
          final partialHtml =
              tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
          expect(partialHtml, contains('Objednávku pak potvrdíš.'));
          expect(partialHtml, isNot(contains('Doplňte údaje')));
          expect(partialHtml, contains('Potvrdit přihlášení'));
          expect(partialHtml, isNot(contains('Legacy expanded')));
        }
        await tester.tap(
          find.widgetWithText(FilledButton, WaitlistStrings.offerPlace),
        );
        await tester.pumpAndSettle();
        expect(sent, hasLength(1));
        expect(sent.single['operation'], 'send');
        expect(sent.single['formId'], 7);
        expect(sent.single['revision'], 77);
        expect(sent.single['recipients'], [
          {'orderId': 5, 'count': count == 2 ? 1 : count},
        ]);
        expect(
          DateTime.parse(sent.single['expiresAt']),
          DateTime.parse('2026-03-29T01:30:00Z'),
        );
        expect(find.byType(WaitlistOffersDialog), findsNothing);
        expect(find.text(WaitlistStrings.text('offerSending')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final succeeds in [true, false]) {
    testWidgetsWithEnvironment(() => _environment,
        'send closes with confirmation only on success: $succeeds', (
      tester,
    ) async {
      bool? result;
      var proposalLoads = 0;
      final sentRevisions = <int>[];
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('open'),
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => WaitlistOffersDialog(
                      form: FormBundle(definition: FormDefinition(id: 7)),
                      loadProposal: (_) async => {
                        'revision': ++proposalLoads,
                        'serverTime': '2026-10-13T12:00:00Z',
                        'offerDurationSeconds': 3600,
                        'capacity': {
                          'enabled': true,
                          'canSendOffers': true,
                          'offerablePlaces': 2,
                        },
                        'recipients': [
                          {'orderId': 5, 'count': 1, 'waitingCount': 1},
                          {'orderId': 6, 'count': 1, 'waitingCount': 1},
                        ],
                      },
                      loadPreview: (_) async => {},
                      executeCommand: (_, payload) async {
                        sentRevisions.add(payload['revision'] as int);
                        return {'code': succeeds ? 200 : 409};
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
      await tester.pumpAndSettle();
      if (succeeds) {
        expect(result, true);
        expect(find.byType(WaitlistOffersDialog), findsNothing);
        expect(
          find.text(WaitlistStrings.text('offersSending')),
          findsOneWidget,
        );
      } else {
        expect(result, isNull);
        expect(find.byType(WaitlistOffersDialog), findsOneWidget);
        expect(find.text(WaitlistStrings.stale), findsOneWidget);
        expect(find.text(WaitlistStrings.refresh), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        await tester.tap(find.text(WaitlistStrings.refresh));
        await tester.pumpAndSettle();
        expect(find.text(WaitlistStrings.stale), findsNothing);
        await tester
            .tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
        await tester.pumpAndSettle();
        expect(sentRevisions, [1, 2]);
        expect(find.text(WaitlistStrings.stale), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgetsWithEnvironment(
    () => _environment,
    'RPC timezone controls preview, picker defaults and UTC submission independently of global timezone',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sent = <Map<String, dynamic>>[];
      expect(tz.local.name, 'Europe/Prague');
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('open zone proof'),
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => WaitlistOffersDialog(
                    form: FormBundle(definition: FormDefinition(id: 7)),
                    loadProposal: (_) async => {
                      'revision': 1,
                      'serverTime': '2027-01-01T01:30:00Z',
                      'offerDurationSeconds': 3600,
                      'capacity': {
                        'enabled': true,
                        'canSendOffers': true,
                        'offerablePlaces': 1,
                      },
                      'recipients': [
                        {'orderId': 5, 'count': 1, 'waitingCount': 1},
                      ],
                    },
                    loadPreview: (_) async => {
                      'timeZone': 'America/New_York',
                      'template': {
                        'subject': 'Date proof',
                        'html':
                            '<span style="white-space:nowrap">{{offer_expires_at}}</span>',
                      },
                    },
                    executeCommand: (_, payload) async {
                      sent.add(payload);
                      return {'code': 200};
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open zone proof'));
      await tester.pumpAndSettle();
      expect(find.textContaining('31. 12. 2026 21:30'), findsOneWidget);
      final preview = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
      expect(preview.replaceAll('\u00a0', ' '), contains('31. 12. 2026 21:30'));
      expect(preview, isNot(contains('1. 1. 2027 03:30')));
      await tester.tap(find.textContaining('31. 12. 2026 21:30'));
      await tester.pumpAndSettle();
      final date = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(date.initialDate, DateTime(2026, 12, 31));
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      final time = tester.widget<TimePickerDialog>(
        find.byType(TimePickerDialog),
      );
      expect(time.initialTime, const TimeOfDay(hour: 21, minute: 30));
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(
        DateTime.parse(sent.single['expiresAt']),
        DateTime.parse('2027-01-01T02:30:00Z'),
      );
      expect(
        tz.local.name,
        'Europe/Prague',
        reason: 'Preview must not alter global settings',
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<List<Map<String, dynamic>>> openBounds(
    WidgetTester tester, {
    Set<int>? selectedOrderIds,
    int capacity = 3,
    int firstLimit = 2,
    int firstCount = 1,
    double width = 1000,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <Map<String, dynamic>>[];
    await _environment.pumpWidget(
      tester,
      RepaintBoundary(
        key: const ValueKey('offer-artifact'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeConfig.theme(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('open bounds'),
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => WaitlistOffersDialog(
                    form: FormBundle(definition: FormDefinition(id: 7)),
                    selectedOrderIds: selectedOrderIds,
                    orders: [
                      OrderModel(
                        id: 5,
                        formId: 7,
                        orderSymbol: '6M1Y3I2F1H',
                        data: {
                          'name': 'Michael Bujnovský',
                          'email': 'bujnmi@example.invalid',
                        },
                      ),
                      OrderModel(
                        id: 6,
                        formId: 7,
                        orderSymbol: '6M1Y3I2F2K',
                        data: {
                          'name': 'Jana Nováková',
                          'email': 'jana@example.invalid',
                        },
                      ),
                    ],
                    loadProposal: (_) async => {
                      'revision': 88,
                      'serverTime': '2026-10-14T12:00:00Z',
                      'offerDurationSeconds': 86400,
                      'capacity': {
                        'enabled': true,
                        'limit': 11,
                        'occupiedPeople': 11 - capacity,
                        'waitingPeople': firstLimit + 2,
                        'canSendOffers': true,
                        'offerablePlaces': capacity,
                      },
                      'recipients': [
                        {
                          'orderId': 5,
                          'count': firstCount,
                          'waitingCount': firstLimit,
                        },
                        {'orderId': 6, 'count': 0, 'waitingCount': 2},
                      ],
                    },
                    loadPreview: (_) async => {
                      'timeZone': 'Europe/Prague',
                      'occasionTitle': 'Podzimní setkání',
                      'toneSubstitutions': {
                        'waitlist_offer_instructions_single':
                            'Doplňte údaje a potvrďte přihlášení.',
                        'waitlist_offer_instructions':
                            'Vyberte osoby a potvrďte přihlášení.',
                      },
                      'instructionsTemplateHtml':
                          '<h2>Uvolnilo se místo</h2><p>{{waitlist_offer_instructions}}</p><p>Nabídka platí do {{offer_expires_at}}.</p>{{offer_button}}',
                    },
                    executeCommand: (_, payload) async {
                      sent.add(payload);
                      return {'code': 200};
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open bounds'));
    await tester.pumpAndSettle();
    return sent;
  }

  testWidgetsWithEnvironment(
    () => _environment,
    'bounds use waiting count, permit reallocating zero proposals and cap the sum',
    (tester) async {
      final sent = await openBounds(tester);
      Finder increase(int id) => find.byKey(ValueKey('offer-increase-$id'));
      Finder select(int id) => find.byKey(ValueKey('offer-select-$id'));
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'Malformed, fractional and negative counts cannot be entered',
      );
      expect(tester.widget<Checkbox>(select(6)).value, false);
      await tester.tap(increase(5));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(increase(5)).onPressed,
        isNull,
        reason: 'Cannot exceed two actual waiting registrations',
      );
      await tester.tap(select(6));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(increase(6)).onPressed,
        isNull,
        reason: 'Other recipients already use all remaining capacity',
      );
      await tester.tap(select(5));
      await tester.pumpAndSettle();
      await tester.tap(increase(6));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(increase(6)).onPressed, isNull);
      await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
      await tester.pumpAndSettle();
      expect(sent.single['recipients'], [
        {'orderId': 6, 'count': 2},
      ]);
      expect(sent.single['revision'], 88);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'selection scope excludes other orders and no selection cannot send',
    (tester) async {
      final sent = await openBounds(
        tester,
        selectedOrderIds: {5},
        firstLimit: 1,
      );
      expect(find.byKey(const ValueKey('offer-select-6')), findsNothing);
      expect(find.byKey(const ValueKey('offer-increase-5')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('offer-select-5')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.text(WaitlistStrings.text('selectOfferRecipient')),
        findsOneWidget,
      );
      expect(sent, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'capacity reduced suggestion is not mistaken for eligible limit',
    (tester) async {
      await openBounds(tester, capacity: 1, firstLimit: 5);
      final increase = find.byKey(const ValueKey('offer-increase-5'));
      expect(
        find.text(
          WaitlistStrings.text('offerCountLimit').replaceAll('{max}', '5'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(increase).onPressed, isNull);
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('offer-select-6')))
            .onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final badCount in [-1, 3]) {
    testWidgetsWithEnvironment(
        () => _environment, 'invalid server count $badCount cannot be sent',
        (tester) async {
      final sent = await openBounds(tester, firstCount: badCount);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text(WaitlistStrings.stale), findsOneWidget);
      expect(sent, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final variant in [
    (width: 320.0, brightness: Brightness.light, scale: 1.0),
    (width: 1000.0, brightness: Brightness.dark, scale: 1.0),
    (width: 320.0, brightness: Brightness.light, scale: 2.0),
  ]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'actual theme layout ${variant.width} ${variant.brightness} scale ${variant.scale}',
      (tester) async {
        await openBounds(
          tester,
          width: variant.width,
          brightness: variant.brightness,
          scale: variant.scale,
          selectedOrderIds: variant.width == 320 ? {5} : null,
          firstLimit: variant.width == 320 ? 1 : 3,
          capacity: variant.width == 320 ? 1 : 4,
        );
        expect(tester.takeException(), isNull);
        if (Platform.environment['WAITLIST_OFFERS_ARTIFACT_DIR']
            case final path?) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('offer-artifact')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory(path).createSync(recursive: true);
            File(
              '$path/offer-${variant.width.toInt()}-${variant.brightness.name}-${variant.scale}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
