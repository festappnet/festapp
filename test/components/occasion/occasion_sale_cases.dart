import 'package:easy_localization/easy_localization.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:fstapp/components/unit/views/occasion_sale_badge.dart';
import 'package:fstapp/components/unit/views/occasion_created_highlight.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_completed.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_result.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:fstapp/widgets/time_data_range_picker.dart';
import 'dart:convert';
import 'package:fstapp/components/occasion/setup/occasion_form_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_customer_preview.dart';
import 'dart:io';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_seat_preview.dart';
import 'package:fstapp/components/occasion/setup/blueprint_setup_layout_draft.dart';
import '../../support/fixtures/blueprint_font_registry_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_sale_status.dart';
import 'package:fstapp/components/occasion/occasion_sale_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_sales.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
  });
  testWidgets(
      'starter admission is human named without changing its price, identity or copied forms',
      (tester) async {
    final configuration = {
      'forms': [
        {
          'fields': [
            {
              'id': -1,
              'type': 'product_type',
              'title': 'Spot',
              'product_type_data': {
                'id': -2,
                'title': 'Spot',
                'type': 'spot',
                'products': [
                  {
                    'id': -3,
                    'title': 'Variant 1',
                    'price': 100,
                    'currency_code': 'CZK'
                  }
                ]
              }
            }
          ]
        }
      ]
    };
    await environment.pumpWidget(tester, const MaterialApp(home: SizedBox()));
    // Localization is supplied by the same fixture as the wizard widgets.
    final starter = defaultDraftForm(configuration);
    final type = starter.relatedFields.single.definition.productType!;
    expect(type.title, 'Vstupné');
    expect(type.products!.single.title, 'Základní vstupenka');
    expect(type.products!.single.id, -3);
    expect(type.products!.single.price, 100);
    final copied = draftFormBundle(
        Map<String, dynamic>.from((configuration['forms'] as List).single));
    expect(copied.products.single.title, 'Variant 1');
  });

  testWidgets(
      'customer preview renders canonical fields and keeps its edits out of the draft',
      (tester) async {
    final data = <String, dynamic>{
      'title': 'Preview',
      'formDraft': {
        'title': 'Form',
        'fields': [
          {'id': null, 'type': 'email', 'title': 'E-mail', 'is_required': true}
        ]
      }
    };
    final saved = jsonEncode(data);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OccasionSetupCustomerPreview(
                    data: data,
                    unitId: 1,
                    draftId: '00000000-0000-4000-8000-000000000001'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Náhled nic neukládá'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'preview@example.invalid');
    await tester.pump();
    expect(jsonEncode(data), saved);
    expect(find.text('Vytvořit objednávku'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preview emails receive entered fields, can retry and are invalidated after editing',
      (tester) async {
    final data = <String, dynamic>{
      'title': 'Preview',
      'formDraft': {
        'fields': [
          {'id': null, 'type': 'email', 'title': 'E-mail', 'is_required': true}
        ]
      }
    };
    final requests = <Map<String, dynamic>>[];
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OccasionSetupCustomerPreview(
          data: data,
          unitId: 1,
          draftId: '00000000-0000-4000-8000-000000000001',
          emailLoader: (input) async {
            requests.add(input);
            if (requests.length == 1) throw StateError('temporary');
            return {
              'messages': [
                {
                  'subject': 'Exact selection',
                  'html': '<p>Preview only</p>',
                  'senderAddress': 'sender@example.invalid'
                }
              ]
            };
          },
        ))));
    await tester.enterText(
        find.byType(TextField).first, 'first@example.invalid');
    await tester.tap(find.text('Ukázat e-maily pro tento výběr'));
    await tester.pumpAndSettle();
    expect(requests.single['fields']['email'], 'first@example.invalid');
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(find.text('Exact selection'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'second@example.invalid');
    await tester.pumpAndSettle();
    expect(find.text('Exact selection'), findsNothing);
    expect(requests.length, 2);
  });

  testWidgets(
      'draft seat picker enforces paired capacity and returns only synthetic identities',
      (tester) async {
    const first = '00000000-0000-4000-8000-000000000011';
    const second = '00000000-0000-4000-8000-000000000012';
    final doc = VenueLayoutDocument(nodes: [
      LayoutNode(id: first, kind: 'seat', label: 'A'),
      LayoutNode(id: second, kind: 'seat', x: 100, label: 'B')
    ]);
    final draft = BlueprintSetupLayoutDraft.empty(document: doc, resources: {})
        .reconcile(doc, defaultProductId: 42);
    OccasionSetupSeatSelection? result;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          child: const Text('Open'),
                          onPressed: () async {
                            result =
                                await showDialog<OccasionSetupSeatSelection>(
                                    context: context,
                                    builder: (_) => OccasionSetupSeatPreview(
                                        draft: draft,
                                        products: [
                                          ProductModel(
                                              id: 42,
                                              title: 'Admission',
                                              price: 100,
                                              currencyCode: 'CZK')
                                        ],
                                        maximum: 1,
                                        loadResources: () async =>
                                            blueprintPreparedResourcesFixture(
                                                doc)));
                          },
                        )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    var picker =
        tester.widget<VenueLayoutPicker>(find.byType(VenueLayoutPicker));
    expect((await picker.onSelectionRequested({first, second}, true)).accepted,
        isFalse);
    expect((await picker.onSelectionRequested({first}, true)).accepted, isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokračovat'));
    await tester.pumpAndSettle();
    expect(result!.seats.single.seat!.id, lessThan(0));
    expect(result!.seats.single.seat!.product!.price, 100);
    expect(draft.seatBindings[first]!.spotId, isNull);
  });

  final now = DateTime.utc(2030, 1, 1, 12);
  OccasionSaleForm form(
          {bool open = true,
          String mode = 'regular',
          bool available = true,
          DateTime? start,
          DateTime? end,
          bool preparation = false,
          bool countdown = false}) =>
      OccasionSaleForm(
          id: 1,
          isOpen: open,
          mode: mode,
          hasAvailability: available,
          start: start,
          end: end,
          isPreparation: preparation,
          countdown: countdown);
  OccasionSaleStatus status(List<OccasionSaleForm> forms) =>
      OccasionSaleStatus.resolve(forms, now: now)!;

  test(
      'form lifecycle distinguishes preparation, pause, deadlines and event end',
      () {
    expect(status([form(open: false, preparation: true)]).state,
        OccasionSaleState.preparation);
    expect(status([form(open: false)]).state, OccasionSaleState.paused);
    expect(status([form(start: now.add(const Duration(hours: 1)))]).state,
        OccasionSaleState.scheduled);
    expect(status([form(start: now)]).state, OccasionSaleState.selling);
    expect(status([form(end: now)]).state, OccasionSaleState.ended);
    expect(status([form(available: false)]).state, OccasionSaleState.soldOut);
    expect(status([form(mode: 'waitlist', available: false)]).state,
        OccasionSaleState.waitlist);
    expect(
        OccasionSaleStatus.resolve([form()], now: now, occasionEnd: now)!.state,
        OccasionSaleState.finished);
    expect(OccasionSaleStatus.resolve([], now: now), isNull);
  });
  test('mixed forms count purchases and waitlists; closed forms do not count',
      () {
    final value = status([
      form(),
      form(mode: 'waitlist'),
      form(open: false),
      form(start: now.add(const Duration(days: 1)))
    ]);
    expect(value.state, OccasionSaleState.selling);
    expect(value.active, 2);
    expect(value.total, 4);
    expect(value.selling, 1);
    expect(value.waitlists, 1);
    final waiting = status([form(mode: 'waitlist'), form(open: false)]);
    expect(waiting.active, 1);
    expect(waiting.state, OccasionSaleState.waitlist);
  });
  test('aggregate never promises an end before the last active form', () {
    final value = status([
      form(end: now.add(const Duration(hours: 1)), countdown: true),
      form(end: now.add(const Duration(hours: 3)), countdown: true)
    ]);
    expect(value.deadline, now.add(const Duration(hours: 3)));
    expect(
        status([form(end: now.add(const Duration(hours: 1))), form()]).deadline,
        isNull);
  });
  test('sale intent validation ignores dormant disabled-form choices', () {
    final data = <String, dynamic>{
      'end': now.add(const Duration(days: 2)).toIso8601String(),
      'saleMode': 'scheduled',
      'saleStart': now.add(const Duration(days: 1)).toIso8601String()
    };
    expect(OccasionSetupSales.valid(data, now), isTrue);
    expect(
        OccasionSetupSales.valid({
          ...data,
          'saleEnd': now.add(const Duration(days: 3)).toIso8601String()
        }, now),
        isFalse);
    expect(
        OccasionSetupSales.valid(
            {...data, 'saleStart': now.toIso8601String()}, now),
        isFalse);
    expect(
        OccasionSetupSales.valid(
            {...data, 'formEnabled': false, 'saleStart': 'broken'}, now),
        isTrue);
  });
  testWidgetsWithEnvironment(
      () => environment, 'sale labels name counts and use Czech plural rules',
      (tester) async {
    expect(OccasionSaleStrings.label(status([form()]), now, const Locale('cs')),
        'V prodeji');
    expect(
        OccasionSaleStrings.label(
            status([form(), form(mode: 'waitlist'), form(open: false)]),
            now,
            const Locale('cs')),
        'V prodeji 2/3');
    expect(
        OccasionSaleStrings.label(
            status([form(mode: 'waitlist'), form(open: false)]),
            now,
            const Locale('cs')),
        'Náhradníci 1/2');
    expect(
        OccasionSaleStrings.label(
            status([
              form(open: false, preparation: true),
              form(open: false, preparation: true)
            ]),
            now,
            const Locale('cs')),
        'V přípravě');
    for (final pair in [
      (1, '1 den'),
      (2, '2 dny'),
      (3, '3 dny'),
      (5, '5 dní'),
      (21, '21 dní')
    ]) {
      expect(
          OccasionSaleStrings.duration(
              Duration(days: pair.$1), const Locale('cs')),
          pair.$2);
    }
    final future = status(
        [form(start: now.add(const Duration(days: 3)), countdown: true)]);
    expect(OccasionSaleStrings.label(future, now, const Locale('cs')),
        'Prodej začíná za 3 dny');
    final ending =
        status([form(end: now.add(const Duration(hours: 2)), countdown: true)]);
    expect(OccasionSaleStrings.label(ending, now, const Locale('cs')),
        'Prodej končí za 2 h');
    final fixed = status([form(start: now.add(const Duration(days: 3)))]);
    expect(OccasionSaleStrings.label(fixed, now, const Locale('cs')),
        startsWith('Prodej od '));
  });
  testWidgetsWithEnvironment(() => environment,
      'scheduled picker stores UTC and countdown never changes the window',
      (tester) async {
    final oldLocation = tz.local;
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
    addTearDown(() => tz.setLocalLocation(oldLocation));
    final today = DateTime.now();
    final selected = DateTime(
        today.year,
        today.month + (today.day >= 26 ? 1 : 0),
        today.day >= 26 ? 2 : today.day + 2);
    final data = <String, dynamic>{
      'saleMode': 'scheduled',
      'end': today.add(const Duration(days: 365)).toUtc().toIso8601String()
    };
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: StatefulBuilder(
                        builder: (context, setState) =>
                            OccasionSetupSaleSettings(
                                data: data,
                                onChanged: (patch) =>
                                    setState(() => data.addAll(patch))))))));
    final dateField = find
        .descendant(
            of: find.byType(TimeDatePicker).first,
            matching: find.byType(TextFormField))
        .last;
    await tester.tap(dateField);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    final calendarContext = tester.element(find.byType(CalendarDatePicker));
    final material = MaterialLocalizations.of(calendarContext);
    if (selected.month != today.month) {
      await tester.tap(find.byTooltip(material.nextMonthTooltip));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${selected.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(material.okButtonLabel));
    await tester.pumpAndSettle();
    final instant =
        tz.TZDateTime(tz.local, selected.year, selected.month, selected.day, 18)
            .toUtc();
    expect(DateTime.parse(data['saleStart']).isAtSameMomentAs(instant), isTrue);
    expect(OccasionSetupSales.valid(data, DateTime.now()), isTrue);
    final savedStart = data['saleStart'];
    final savedEnd = data['end'];
    final countdown = find.byType(CheckboxListTile);
    await tester.ensureVisible(countdown);
    await tester.tap(countdown);
    await tester.pumpAndSettle();
    expect(data['saleCountdown'], true);
    await tester.tap(countdown);
    await tester.pumpAndSettle();
    expect(data['saleCountdown'], false);
    expect(data['saleStart'], savedStart);
    expect(data['end'], savedEnd);
    expect(tester.takeException(), isNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'completion closes before its caller navigates to list or administration',
      (tester) async {
    OccasionSetupNext? next;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          next = await Navigator.of(context)
                              .push<OccasionSetupNext>(MaterialPageRoute(
                                  builder: (_) => const OccasionSetupCompleted(
                                      result: OccasionSetupResult(
                                          occasionId: 1,
                                          unit: 1,
                                          link: 'event',
                                          title: 'Akce',
                                          formLink: 'saved-form'))));
                        },
                        child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Kopírovat'), findsOneWidget);
    await tester.tap(find.text('Spravovat akci'));
    await tester.pumpAndSettle();
    expect(next, OccasionSetupNext.manage);
    expect(find.byType(OccasionSetupCompleted), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Přejít do přehledu akcí'));
    await tester.pumpAndSettle();
    expect(next, OccasionSetupNext.list);
    expect(find.byType(OccasionSetupCompleted), findsNothing);
  });

  for (final animate in [true, false]) {
    testWidgets(
        'new occasion is revealed beyond the lazy viewport, animate=$animate',
        (tester) async {
      final grid = GlobalKey();
      final controller = ScrollController();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 500,
                  height: 500,
                  child: CustomScrollView(controller: controller, slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 300)),
                    SliverGrid(
                        key: grid,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 250,
                                mainAxisExtent: 126,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16),
                        delegate: SliverChildBuilderDelegate(
                            (context, i) => Text('Event $i'),
                            childCount: 100)),
                    const SliverToBoxAdapter(child: SizedBox(height: 64)),
                  ])))));
      expect(find.text('Event 72'), findsNothing);
      final revealed = OccasionCreatedHighlight.reveal(
          gridKey: grid, controller: controller, index: 72, animate: animate);
      await tester.pumpAndSettle();
      await revealed;
      final rect = tester.getRect(find.text('Event 72'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgetsWithEnvironment(() => environment,
      'ordinary open cards retain original typography and hide sale decoration',
      (tester) async {
    final occasion = OccasionModel(
        id: 1,
        title: 'Původní karta',
        startTime: DateTime(2030, 1, 10),
        endTime: DateTime(2030, 1, 11),
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        stats: StatsModel(),
        saleForms: [form(), form()]);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 312,
                    height: 110,
                    child:
                        OccasionEditCard(occasion: occasion, onTap: () {})))));
    expect(find.byType(TextButton), findsNothing);
    final title = tester.widget<Text>(find.text('Původní karta'));
    expect(title.maxLines, 1);
    expect(title.style!.fontSize, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'paused card shows its label and lock with keyboard and tap details',
      (tester) async {
    var opened = 0;
    final occasion = OccasionModel(
        id: 1,
        title: 'Pozastavená akce',
        startTime: DateTime(2030, 1, 10),
        endTime: DateTime(2030, 1, 11),
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        stats: StatsModel(),
        saleForms: [form(open: false)]);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 312,
                    height: 110,
                    child: OccasionEditCard(
                        occasion: occasion, onTap: () => opened++)))));
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    final icon = tester.getRect(find.byIcon(Icons.lock_outline));
    final card = tester.getRect(find.byType(OccasionEditCard));
    final labelRect = tester.getRect(find.text('Pozastaveno'));
    expect(labelRect.right, greaterThan(card.right - 24));
    expect(icon.right, lessThan(labelRect.left));
    final dateRect =
        tester.getRect(find.byKey(const ValueKey('occasion-card-date')));
    expect((labelRect.center.dy - dateRect.center.dy).abs(), lessThan(2));
    expect(labelRect.top, greaterThanOrEqualTo(card.top + 12));
    expect(dateRect.right, lessThanOrEqualTo(icon.left));
    expect(icon.top, greaterThanOrEqualTo(card.top + 12));
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.style!.backgroundColor!.resolve({}), Colors.transparent);
    for (var i = 0;
        i < 4 && find.textContaining('Pozastaveno\n').evaluate().isEmpty;
        i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Pozastaveno\n'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump();
    expect(find.textContaining('Pozastaveno\n'), findsOneWidget);
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgetsWithEnvironment(() => environment,
        'card fits 288px at text scale $scale and explains its badge',
        (tester) async {
      var opened = 0;
      final occasion = OccasionModel(
          id: 1,
          title:
              'Velmi dlouhý název společenského večera pro přátele a sousedy',
          startTime: DateTime(2030, 1, 10),
          endTime: DateTime(2030, 1, 11),
          isOpen: false,
          isHidden: true,
          isPromoted: false,
          stats: StatsModel(),
          saleForms: [form(), form(mode: 'waitlist'), form(open: false)]);
      await environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: MediaQuery(
                      data:
                          MediaQueryData(textScaler: TextScaler.linear(scale)),
                      child: SizedBox(
                          width: 288,
                          height: 110 + (scale - 1) * 64,
                          child: OccasionEditCard(
                              occasion: occasion, onTap: () => opened++))))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('V prodeji 2/3'), findsNothing);
      await tester.tap(find.text('2/3'));
      await tester.pump();
      expect(find.textContaining('Otevřené formuláře: 2/3'), findsOneWidget);
      expect(opened, 0,
          reason: 'Opening status must not navigate to the occasion');
      expect(tester.takeException(), isNull);
    });
  }
  for (final state in [...OccasionSaleState.values, null]) {
    testWidgetsWithEnvironment(
        () => environment, 'card mutes only inactive sales: $state',
        (tester) async {
      final instant = DateTime.now().toUtc();
      final forms = switch (state) {
        OccasionSaleState.preparation => [form(open: false, preparation: true)],
        OccasionSaleState.scheduled => [
            form(start: instant.add(const Duration(days: 4)))
          ],
        OccasionSaleState.paused => [form(open: false)],
        OccasionSaleState.soldOut => [form(available: false)],
        OccasionSaleState.waitlist => [
            form(
                mode: 'waitlist',
                countdown: true,
                end: instant.add(const Duration(days: 1))),
            form(open: false)
          ],
        OccasionSaleState.ended => [
            form(end: instant.subtract(const Duration(days: 1)))
          ],
        null => null,
        _ => [form()],
      };
      var opened = 0;
      final occasion = OccasionModel(
          id: 1,
          title: 'Stav události',
          startTime: DateTime(2030, 1, 10),
          endTime: DateTime(2030, 1, 11),
          isOpen: true,
          isHidden: false,
          isPromoted: false,
          stats: StatsModel(),
          saleForms: forms,
          saleOccasionEndUtc: state == OccasionSaleState.finished
              ? instant.subtract(const Duration(days: 1))
              : null);
      await environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: SizedBox(
                      width: 312,
                      height: 110,
                      child: OccasionEditCard(
                          occasion: occasion, onTap: () => opened++)))));
      final inactive = state != null &&
          state != OccasionSaleState.selling &&
          state != OccasionSaleState.waitlist;
      expect(
          tester
              .widget<Opacity>(
                  find.byKey(const ValueKey('occasion-sale-content')))
              .opacity,
          inactive ? lessThan(1.0) : equals(1.0));
      if (state == OccasionSaleState.waitlist) {
        expect(find.text('Náhradníci 1/2'), findsOneWidget);
        final tooltip = tester.widget<Tooltip>(find.ancestor(
            of: find.byType(TextButton), matching: find.byType(Tooltip)));
        expect(tooltip.message, contains('Prodej končí:'));
        expect(tooltip.message, isNot(contains('Prodej začíná:')));
      }
      if (state == OccasionSaleState.finished) {
        expect(find.byType(OccasionSaleBadge), findsNothing);
        expect(find.text('Proběhlo'), findsNothing);
      }
      if (state == OccasionSaleState.soldOut) {
        expect(find.text('Vyprodáno'), findsOneWidget);
      }
      await tester.tap(find.text('Stav události'));
      expect(opened, 1, reason: 'Muted cards must remain navigable');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final countdown in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgetsWithEnvironment(() => environment,
          'scheduled label preserves date at scale $scale, countdown $countdown',
          (tester) async {
        final start =
            DateTime.now().toUtc().add(const Duration(days: 3, hours: 12));
        final occasion = OccasionModel(
            id: 1,
            title: 'Naplánovaná událost',
            startTime: DateTime(2030, 12, 28),
            endTime: DateTime(2031, 1, 3),
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            stats: StatsModel(),
            saleForms: [form(start: start, countdown: countdown)]);
        await environment.pumpWidget(
            tester,
            MaterialApp(
                home: Scaffold(
                    body: MediaQuery(
                        data: MediaQueryData(
                            textScaler: TextScaler.linear(scale)),
                        child: SizedBox(
                            width: 288,
                            height: 110 + (scale - 1) * 64,
                            child: OccasionEditCard(
                                occasion: occasion, onTap: () {}))))));
        final label = find.text('Začíná za 3 dny');
        expect(label, findsOneWidget);
        final date = find.byKey(const ValueKey('occasion-card-date'));
        expect(
            (tester.getRect(label).center.dy - tester.getRect(date).center.dy)
                .abs(),
            lessThan(2));
        expect(tester.getRect(label).overlaps(tester.getRect(date)), isFalse);
        expect(
            tester
                .widget<Text>(find.text('Naplánovaná událost'))
                .style!
                .fontSize,
            16);
        final tooltip = tester.widget<Tooltip>(find.ancestor(
            of: find.byType(TextButton), matching: find.byType(Tooltip)));
        expect(tooltip.message, contains('Prodej začíná:'));
        expect(tooltip.message, isNot(contains('Prodej končí:')));
        expect(find.textContaining('Prodej od'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgetsWithEnvironment(
        () => environment, 'real font header stays inset in $brightness',
        (tester) async {
      await tester.runAsync(() async {
        final loader = FontLoader('CardPreviewFutura');
        loader.addFont(Future.value(ByteData.sublistView(
            await File('fonts/Futura PT Medium.ttf').readAsBytes())));
        await loader.load();
        if (const bool.fromEnvironment('OCCASION_CARD_PREVIEW')) {
          final icons = FontLoader('MaterialIcons');
          icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        }
      });
      await tester.binding.setSurfaceSize(const Size(1024, 160));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      final now = DateTime.now().toUtc();
      await environment.pumpWidget(
          tester,
          Builder(
              builder: (context) => MaterialApp(
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    localizationsDelegates: context.localizationDelegates,
                    theme: ThemeData(
                        brightness: brightness,
                        fontFamily: 'CardPreviewFutura'),
                    home: Scaffold(
                        body: RepaintBoundary(
                            key: boundary,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                for (final mode in [
                                  'paused',
                                  'scheduled',
                                  'past'
                                ])
                                  SizedBox(
                                      width: 320,
                                      height: 110,
                                      child: OccasionEditCard(
                                          occasion: OccasionModel(
                                              id: 1,
                                              title: 'Setkání pořadatelů',
                                              startTime: mode == 'past'
                                                  ? now.subtract(
                                                      const Duration(days: 4))
                                                  : DateTime(2030, 11, 20),
                                              endTime: mode == 'past'
                                                  ? now.subtract(
                                                      const Duration(days: 1))
                                                  : DateTime(2030, 11, 23),
                                              isOpen: true,
                                              isHidden: false,
                                              isPromoted: false,
                                              stats: StatsModel(),
                                              saleForms: mode == 'paused'
                                                  ? [form(open: false)]
                                                  : mode == 'scheduled'
                                                      ? [
                                                          form(
                                                              start: now.add(
                                                                  const Duration(
                                                                      days: 2,
                                                                      hours:
                                                                          12)))
                                                        ]
                                                      : null),
                                          onTap: () {})),
                              ]),
                            ))),
                  )));
      await tester.pumpAndSettle();
      expect(find.text('Začíná za 2 dny'), findsOneWidget);
      expect(find.text('Proběhlo'), findsNothing);
      expect(find.byType(OccasionSaleBadge), findsNWidgets(2));
      for (final label in ['Pozastaveno', 'Začíná za 2 dny']) {
        expect(
            (tester.renderObject(find.text(label)) as RenderParagraph)
                .didExceedMaxLines,
            isFalse);
        final rect = tester.getRect(find.text(label));
        final card = tester.getRect(
            find.ancestor(of: find.text(label), matching: find.byType(Card)));
        expect(rect.top, greaterThanOrEqualTo(card.top + 12));
        expect(rect.right, lessThanOrEqualTo(card.right - 8));
      }
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('OCCASION_CARD_PREVIEW')) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/occasion-card-header-${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgetsWithEnvironment(() => environment,
      'one card tick updates both resolved status and inactive treatment',
      (tester) async {
    final occasion = OccasionModel(
        id: 1,
        title: 'Průběžný stav',
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        saleForms: [form(open: false)]);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 312,
                    height: 110,
                    child:
                        OccasionEditCard(occasion: occasion, onTap: () {})))));
    expect(find.text('Pozastaveno'), findsOneWidget);
    // Change the projected window without rebuilding the widget. The card's
    // clock must resolve it again, together with its presentation.
    occasion.saleForms = [
      form(start: DateTime.now().toUtc().subtract(const Duration(seconds: 1)))
    ];
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(TextButton), findsNothing);
    expect(
        tester
            .widget<Opacity>(
                find.byKey(const ValueKey('occasion-sale-content')))
            .opacity,
        1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });
}
