import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:fstapp/components/forms/views/waitlist_offers_dialog.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/waitlist_summary_model.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
    zones.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  });
  for (final count in [1, 2, 5]) {
    testWidgets(
        'focused offer sends only selected registration and expands inherited preview for$count',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final form = FormModel(id: 7, waitlistEnabled: true);
      final selected = OrderModel(
          id: 5,
          formId: 7,
          state: 'waitlisted',
          orderSymbol: 'SELECTED5',
          data: {'name': 'Jana Nováková', 'email': 'jana@example.invalid'});
      selected.waitlistSummary = WaitlistSummaryModel.fromJson({
        'counts': {'waiting': count}
      });
      final other = OrderModel(
          id: 6, formId: 7, state: 'waitlisted', orderSymbol: 'OTHER6');
      final sent = <Map<String, dynamic>>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(context: context, builder: (_) => WaitlistOffersDialog(
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
              'offerablePlaces': count + 1
            },
            'recipients': [
              {'orderId': 5, 'count': count},
              {'orderId': 6, 'count': 1}
            ]
          };
        },
        loadPreview: (id) async => {
          'occasionTitle': 'Festival <test>',
          'toneSubstitutions': {
            'waitlist_offer_button_single': 'Potvrdit přihlášení',
            'waitlist_offer_button_multiple': 'Potvrdit vybrané osoby',
            'waitlist_manage_button_label': 'Spravovat čekání',
            'waitlist_offer_heading': count == 2 ? 'Máme pro tebe nabídku' : 'Máme pro vás nabídku',
            'waitlist_offer_instructions_single': 'Doplňte údaje a potvrďte přihlášení.',
            'waitlist_offer_instructions': count == 2 ? 'Objednávku pak potvrdíš.' : 'Objednávku pak potvrdíte.',
          },
          'instructionsTemplateHtml':
              '<h2>{{waitlist_offer_heading}}</h2><p>{{waitlist_offer_instructions}}</p><p>{{participant_phrase}} | {{participant_count}} | {{offered_count}} | <span style="white-space:nowrap">{{offer_expires_at}}</span></p><p>{{occasion_title}}</p>{{offer_button}}',
          'template': {
            'subject': 'Nabídka pro {{offered_places}}',
            'html':
                '<h2>{{waitlist_offer_heading}}</h2><p>Legacy expanded multi-person instructions.</p><p>{{participant_phrase}} | {{participant_count}} | {{offered_count}} | <span style="white-space:nowrap">{{offer_expires_at}}</span></p><p>{{occasion_title}}</p>{{offer_button}}'
          },
          'wrapper': {'html': '<main>{{content}}</main>'},
        },
        executeCommand: (operation, payload) async {
          sent.add({'operation': operation, ...payload});
          return {'code': 200};
        },
      )), child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .labelText,
          contains('Jana Nováková'));
      expect(find.textContaining('OTHER6'), findsNothing);
      expect(find.text(WaitlistStrings.offerReviewExplanation), findsOneWidget);
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
      expect(html, contains(count == 2 ? 'Máme pro tebe nabídku' : 'Máme pro vás nabídku'));
      expect(html, contains(count == 1 ? 'Doplňte údaje a potvrďte přihlášení.' : count == 2 ? 'Objednávku pak potvrdíš.' : 'Objednávku pak potvrdíte.'));
      expect(html, contains(count == 1 ? 'Potvrdit přihlášení' : 'Potvrdit vybrané osoby'));
      expect(html, contains(people));
      expect(html, contains(places));
      expect(html.replaceAll('\u00a0', ' '), contains('29. 3. 2026 03:30'));
      expect(html, contains('white-space:nowrap'));
      expect(html, contains('29.\u00a03.\u00a02026\u00a003:30'));
      expect(html, contains('Festival &lt;test&gt;'));
      expect(html, isNot(contains('Europe')));
      expect(html, isNot(contains('UTC')));
      expect(html, isNot(contains('{{')));
      if (count == 2) {
        await tester.enterText(find.byType(TextField), '1');
        await tester.pumpAndSettle();
        final partialHtml = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
        expect(partialHtml, contains('Objednávku pak potvrdíš.'));
        expect(partialHtml, isNot(contains('Doplňte údaje')));
        expect(partialHtml, contains('Potvrdit přihlášení'));
        expect(partialHtml, isNot(contains('Legacy expanded')));
      }
      await tester
          .tap(find.widgetWithText(FilledButton, WaitlistStrings.offerPlace));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['operation'], 'send');
      expect(sent.single['formId'], 7);
      expect(sent.single['revision'], 77);
      expect(sent.single['recipients'], [
        {'orderId': 5, 'count': count == 2 ? 1 : count}
      ]);
      expect(DateTime.parse(sent.single['expiresAt']),
          DateTime.parse('2026-03-29T01:30:00Z'));
      expect(find.byType(WaitlistOffersDialog), findsNothing);
      expect(find.text(WaitlistStrings.text('offerSending')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final succeeds in [true, false]) {
    testWidgets('send closes with confirmation only on success: $succeeds', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) => TextButton(child: const Text('open'), onPressed: () async {
          result = await showDialog<bool>(context: context, builder: (_) => WaitlistOffersDialog(
            form: FormModel(id: 7),
            loadProposal: (_) async => {
              'revision': 1, 'serverTime': '2026-10-13T12:00:00Z', 'offerDurationSeconds': 3600,
              'capacity': {'enabled': true, 'canSendOffers': true, 'offerablePlaces': 2},
              'recipients': [{'orderId': 5, 'count': 1}, {'orderId': 6, 'count': 1}],
            },
            loadPreview: (_) async => {},
            executeCommand: (_, __) async => {'code': succeeds ? 200 : 409},
          ));
        }),
      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
      await tester.pumpAndSettle();
      if (succeeds) {
        expect(result, true);
        expect(find.byType(WaitlistOffersDialog), findsNothing);
        expect(find.text(WaitlistStrings.text('offersSending')), findsOneWidget);
      } else {
        expect(result, isNull);
        expect(find.byType(WaitlistOffersDialog), findsOneWidget);
        expect(find.text(WaitlistStrings.stale), findsOneWidget);
        expect(find.text(WaitlistStrings.refresh), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('RPC timezone controls preview, picker defaults and UTC submission independently of global timezone', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <Map<String, dynamic>>[];
    expect(tz.local.name, 'Europe/Prague');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      child: const Text('open zone proof'),
      onPressed: () => showDialog<bool>(context: context, builder: (_) => WaitlistOffersDialog(
        form: FormModel(id: 7),
        loadProposal: (_) async => {
          'revision': 1, 'serverTime': '2027-01-01T01:30:00Z', 'offerDurationSeconds': 3600,
          'capacity': {'enabled': true, 'canSendOffers': true, 'offerablePlaces': 1},
          'recipients': [{'orderId': 5, 'count': 1}],
        },
        loadPreview: (_) async => {
          'timeZone': 'America/New_York',
          'template': {'subject': 'Date proof', 'html': '<span style="white-space:nowrap">{{offer_expires_at}}</span>'},
        },
        executeCommand: (_, payload) async { sent.add(payload); return {'code': 200}; },
      )),
    )))));
    await tester.tap(find.text('open zone proof'));
    await tester.pumpAndSettle();
    expect(find.textContaining('31. 12. 2026 21:30'), findsOneWidget);
    final preview = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
    expect(preview.replaceAll('\u00a0', ' '), contains('31. 12. 2026 21:30'));
    expect(preview, isNot(contains('1. 1. 2027 03:30')));
    await tester.tap(find.textContaining('31. 12. 2026 21:30'));
    await tester.pumpAndSettle();
    final date = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(date.initialDate, DateTime(2026, 12, 31));
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    final time = tester.widget<TimePickerDialog>(find.byType(TimePickerDialog));
    expect(time.initialTime, const TimeOfDay(hour: 21, minute: 30));
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
    expect(DateTime.parse(sent.single['expiresAt']), DateTime.parse('2027-01-01T02:30:00Z'));
    expect(tz.local.name, 'Europe/Prague', reason: 'Preview must not alter global settings');
    expect(tester.takeException(), isNull);
  });

}
