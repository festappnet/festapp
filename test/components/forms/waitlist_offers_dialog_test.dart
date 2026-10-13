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
              body: WaitlistOffersDialog(
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
          'template': {
            'subject': 'Nabídka pro {{offered_places}}',
            'html':
                '<p>{{participant_phrase}} | {{participant_count}} | {{offered_count}} | {{offer_expires_at}}</p><p>{{occasion_title}}</p>{{offer_button}}'
          },
          'wrapper': {'html': '<main>{{content}}</main>'},
        },
        executeCommand: (operation, payload) async {
          sent.add({'operation': operation, ...payload});
          return {'code': 200};
        },
      ))));
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
      await tester.tap(find.widgetWithText(ExpansionTile, 'SELECTED5'));
      await tester.pumpAndSettle();
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
      expect(html, contains(people));
      expect(html, contains(places));
      expect(html, contains('29. 3. 2026 03:30'));
      expect(html, contains('Festival &lt;test&gt;'));
      expect(html, isNot(contains('Europe')));
      expect(html, isNot(contains('UTC')));
      expect(html, isNot(contains('{{')));
      await tester
          .tap(find.widgetWithText(FilledButton, WaitlistStrings.offerPlace));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['operation'], 'send');
      expect(sent.single['formId'], 7);
      expect(sent.single['revision'], 77);
      expect(sent.single['recipients'], [
        {'orderId': 5, 'count': count}
      ]);
      expect(DateTime.parse(sent.single['expiresAt']),
          DateTime.parse('2026-03-29T01:30:00Z'));
      expect(find.text(WaitlistStrings.queued), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
