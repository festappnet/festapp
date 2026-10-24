import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_delivery_selector.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_email_preview.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_delivery_preview.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_due_settings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_sales.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_communication_settings.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });

  test('scheduled opening defaults once to 24 hours and preserves edits', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    final draft = <String, dynamic>{
      'end': now.add(const Duration(days: 5)).toIso8601String(),
    };
    OccasionSetupSales.select(draft, 'scheduled', now);
    expect(DateTime.parse(draft['saleStart'] as String),
        now.add(const Duration(hours: 24)));
    final chosen = now.add(const Duration(days: 2)).toIso8601String();
    draft['saleStart'] = chosen;
    OccasionSetupSales.select(draft, 'preparation', now);
    OccasionSetupSales.select(
        draft, 'scheduled', now.add(const Duration(hours: 1)));
    expect(draft['saleStart'], chosen);
    expect(OccasionSetupSales.valid(draft, now), isTrue);
  });

  test('sales reject expired or reversed intervals and ends after event', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    final draft = <String, dynamic>{
      'saleMode': 'scheduled',
      'saleStart': now.add(const Duration(days: 1)).toIso8601String(),
      'saleEnd': now.add(const Duration(days: 2)).toIso8601String(),
      'end': now.add(const Duration(days: 3)).toIso8601String(),
    };
    expect(OccasionSetupSales.valid(draft, now), isTrue);
    draft['saleStart'] = now.toIso8601String();
    expect(OccasionSetupSales.valid(draft, now), isFalse);
    draft['saleStart'] = draft['saleEnd'];
    expect(OccasionSetupSales.valid(draft, now), isFalse);
    draft['saleStart'] = now.add(const Duration(days: 1)).toIso8601String();
    draft['saleEnd'] = now.add(const Duration(days: 4)).toIso8601String();
    expect(OccasionSetupSales.valid(draft, now), isFalse);
    draft['saleMode'] = 'immediate';
    draft['saleEnd'] = now.toIso8601String();
    expect(OccasionSetupSales.valid(draft, now), isFalse);
  });

  test('short event does not silently replace an invalid 24 hour default', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    final draft = <String, dynamic>{
      'end': now.add(const Duration(hours: 12)).toIso8601String(),
    };
    OccasionSetupSales.select(draft, 'scheduled', now);
    expect(DateTime.parse(draft['saleStart'] as String),
        now.add(const Duration(hours: 24)));
    expect(OccasionSetupSales.valid(draft, now), isFalse);
  });

  test('reminder validates visible explicit and inherited timing only', () {
    final meta = <String, dynamic>{};
    final draft = <String, dynamic>{
      'formDraft': <String, dynamic>{'data': meta},
      'reminderLeadDays': '-1',
    };
    expect(OccasionSetupDueSettings.validReminder(draft), isTrue);
    expect(
        OccasionSetupDueSettings.validReminder(draft, inheritedEnabled: true),
        isFalse);
    meta['is_reminder_enabled'] = true;
    expect(OccasionSetupDueSettings.validReminder(draft), isFalse);
    draft['reminderLeadDays'] = '0';
    expect(OccasionSetupDueSettings.validReminder(draft), isTrue);
    draft['reminderLeadDays'] = 'invalid';
    expect(OccasionSetupDueSettings.validReminder(draft), isFalse);
    meta['is_reminder_enabled'] = false;
    expect(
        OccasionSetupDueSettings.validReminder(draft, inheritedEnabled: true),
        isTrue);
  });

  test('due days retain zero and reject invalid durations', () {
    expect(OccasionSetupDueSettings.validDays('0'), isTrue);
    expect(OccasionSetupDueSettings.validDays('0,5'), isTrue);
    for (final value in ['-1', '', 'abc', 'NaN', 'Infinity']) {
      expect(OccasionSetupDueSettings.validDays(value), isFalse);
    }
  });

  testWidgetsWithEnvironment(() => environment,
      'due display preserves inheritance; editing and reset only change draft',
      (tester) async {
    final draft = <String, dynamic>{
      'id': 'due',
      'formDraft': <String, dynamic>{'data': <String, dynamic>{}}
    };
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: StatefulBuilder(
                    builder: (context, setState) => OccasionSetupDueSettings(
                        draft: draft,
                        inheritedDeadlineSeconds: 172800,
                        onChanged: (change) =>
                            setState(() => change(draft)))))));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect((draft['formDraft'] as Map).containsKey('deadline_duration_seconds'),
        isFalse);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();
    expect((draft['formDraft'] as Map)['deadline_duration_seconds'], 0);
    await tester.tap(find.byType(TextButton).first);
    await tester.pump();
    expect((draft['formDraft'] as Map)['deadline_duration_seconds'], isNull);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(((draft['formDraft'] as Map)['data'] as Map)['is_reminder_enabled'],
        isTrue);
  });

  testWidgetsWithEnvironment(() => environment,
      'communication preview ignores stale response and preserves inherited tone',
      (tester) async {
    final draft = <String, dynamic>{
      'id': 'preview',
      'formDraft': <String, dynamic>{'data': <String, dynamic>{}}
    };
    final requests = <Completer<Map<String, dynamic>>>[];
    final snapshots = <Map<String, dynamic>>[];
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: StatefulBuilder(
                        builder: (context, setState) =>
                            OccasionSetupCommunicationSettings(
                                draft: draft,
                                onChanged: (change) =>
                                    setState(() => change(draft)),
                                loadPreview: (snapshot) {
                                  snapshots.add(snapshot);
                                  final request =
                                      Completer<Map<String, dynamic>>();
                                  requests.add(request);
                                  return request.future;
                                }))))));
    await tester.pump(const Duration(milliseconds: 301));
    expect(requests.length, 1);
    expect(
        ((draft['formDraft'] as Map)['data'] as Map)
            .containsKey('communication_tone'),
        isFalse);
    await tester.tap(find.byType(ChoiceChip).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    expect(requests.length, 2);
    expect(
        ((snapshots.first['formDraft'] as Map)['data'] as Map)
            .containsKey('communication_tone'),
        isFalse);
    requests.last.complete(
        {'subject': 'Current preview', 'html': '<p>Current body</p>'});
    await tester.pump();
    await tester.pump();
    requests.first
        .complete({'subject': 'Stale preview', 'html': '<p>Stale body</p>'});
    await tester.pump();
    expect(find.text('Current preview'), findsOneWidget);
    expect(find.text('Stale preview'), findsNothing);
    expect(((draft['formDraft'] as Map)['data'] as Map)['communication_tone'],
        'informal');
  });
  testWidgetsWithEnvironment(() => environment,
      'ticket preview switches count and delivery locally with shared HTML view',
      (tester) async {
    var calls = 0;
    var mode = TicketDeliveryMode.both;
    late StateSetter update;
    Future<Map<String, dynamic>> load() async {
      calls++;
      return {
        'title': 'Preview event',
        'resolved': {
          'template': {
            'subject': '{{occasionTitle}}',
            'html': '<p style="text-align: center">Sample body</p>{{tickets}}',
          },
          'wrapper': {'html': '<main>{{content}}</main>'},
        },
      };
    }

    await environment.pumpWidget(tester, MaterialApp(home: Scaffold(body:
        SingleChildScrollView(
            child: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return TicketDeliveryPreview(revision: 1, mode: mode, load: load);
    })))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(HtmlView), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ticket_UKAZKA-1.pdf'), findsOneWidget);
    expect(tester.widget<HtmlView>(find.byType(HtmlView)).html,
        contains('text-align: center'));
    await tester.tap(find.widgetWithText(ChoiceChip, '3 vstupenky'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(QrImageView), findsNWidgets(3));
    expect(find.text('ticket_UKAZKA-3.pdf'), findsOneWidget);
    update(() => mode = TicketDeliveryMode.inlineQr);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNWidgets(3));
    expect(find.text('ticket_UKAZKA-1.pdf'), findsNothing);
    update(() => mode = TicketDeliveryMode.pdfAttachment);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('ticket_UKAZKA-3.pdf'), findsOneWidget);
    expect(calls, 1);
  });

  test('ticket mode defaults only when absent and survives layout roundtrips',
      () {
    final legacy =
        TicketFeature.fromJson({'code': 'ticket', 'is_enabled': true});
    expect(legacy.deliveryMode, TicketDeliveryMode.pdfAttachment);
    for (final mode in TicketDeliveryMode.values) {
      final feature = TicketFeature.fromJson({
        'code': 'ticket',
        'is_enabled': false,
        'delivery_mode': mode.value,
        'layout': {'schemaVersion': 3, 'templates': {}}
      });
      feature.loadSavedLayout({'schemaVersion': 3, 'templates': {}});
      final copy = TicketFeature.fromJson(feature.toJson());
      expect(copy.deliveryMode, mode);
      expect(copy.isEnabled, isFalse);
      expect(copy.layout, isNotNull);
    }
    for (final invalid in [null, '', 'qr', 1]) {
      expect(
          () => TicketFeature.fromJson(
              {'code': 'ticket', 'delivery_mode': invalid}),
          throwsFormatException);
    }
  });

  test('preview only projects server sample PNGs and strips template resources',
      () {
    final png = base64Encode([137, 80, 78, 71, 13, 10, 26, 10, 0]);
    final safe = TicketEmailPreview.safeHtml(
        '<p style="background:url(https://example.test)" onclick="bad()">Text</p>'
        '<img src="cid:sample"><img src="https://example.test/a.png">'
        '<img src="data:image/png;base64,$png"><script>bad()</script>'
        '<a href="https://example.test">link</a>',
        [
          {'contentId': 'sample', 'content': png}
        ]);
    expect('data:image/png'.allMatches(safe).length, 1);
    expect(safe, isNot(contains('https:')));
    expect(safe, isNot(contains('onclick')));
    expect(safe, isNot(contains('script')));
    expect(safe, contains('Text'));
    expect(
        TicketEmailPreview.safeHtml('<img src="cid:bad">', [
          {
            'contentId': 'bad',
            'content': base64Encode([1, 2, 3])
          }
        ]),
        isNot(contains('<img')));
  });

  testWidgetsWithEnvironment(() => environment,
      'communication preserves layout and previews ticket mode separately from confirmation',
      (tester) async {
    final draft = <String, dynamic>{
      'id': 'tickets',
      'eventKind': 'concert',
      'ticketDraft': <String, dynamic>{
        'code': 'ticket',
        'is_enabled': true,
        'layout': {'schemaVersion': 3, 'templates': {}}
      },
      'formDraft': <String, dynamic>{'data': <String, dynamic>{}}
    };
    final snapshots = <Map<String, dynamic>>[];
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: StatefulBuilder(
                        builder: (context, setState) =>
                            OccasionSetupCommunicationSettings(
                                draft: draft,
                                onChanged: (change) =>
                                    setState(() => change(draft)),
                                loadPreview: (snapshot) async {
                                  snapshots.add(snapshot);
                                  return {
                                    'subject': snapshot['previewMessageType'] ??
                                        'confirmation',
                                    'html': '<p>Sample</p>'
                                  };
                                }))))));
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(snapshots.any((s) => s['previewMessageType'] == 'order_tickets'),
        isTrue);
    expect(snapshots.any((s) => s['previewMessageType'] == null), isTrue);
    final inline = find.widgetWithText(
        RadioListTile<TicketDeliveryMode>, 'QR přímo v e-mailu');
    await tester.ensureVisible(inline);
    await tester.tap(inline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect((draft['ticketDraft'] as Map)['delivery_mode'], 'inline_qr');
    expect((draft['ticketDraft'] as Map)['layout'], isNotNull);
    expect((draft['formDraft'] as Map).containsKey('delivery_mode'), isFalse);
    expect(
        (snapshots.last['ticketDraft'] as Map)['delivery_mode'], 'inline_qr');
    expect(draft.containsKey('previewMessageType'), isFalse);
    final pdf =
        find.widgetWithText(RadioListTile<TicketDeliveryMode>, 'PDF v příloze');
    await tester.ensureVisible(pdf);
    await tester.tap(pdf);
    await tester.pump();
    expect((draft['ticketDraft'] as Map)['delivery_mode'], 'pdf_attachment');
    expect((draft['ticketDraft'] as Map)['layout'], isNotNull);
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
  });

  testWidgetsWithEnvironment(() => environment,
      'disabled tickets preserve mode and disable the three choices',
      (tester) async {
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: TicketDeliverySelector(
                    value: TicketDeliveryMode.both,
                    enabled: false,
                    onChanged: (_) =>
                        fail('Disabled selector must not write')))));
    final choices = tester
        .widgetList<RadioListTile<TicketDeliveryMode>>(
            find.byType(RadioListTile<TicketDeliveryMode>))
        .toList();
    expect(choices.length, 3);
    expect(choices.every((choice) => choice.onChanged == null), isTrue);
    expect(
        choices.every((choice) => choice.groupValue == TicketDeliveryMode.both),
        isTrue);
  });
  test('reserved ticket substitution has no client-generated QR default', () {
    final ticketSubs = EmailTemplateModel
        .substitutionDefinitions['TICKET_ORDER_PAYMENT_DONE']!;
    final blocks = ticketSubs.where((sub) => sub.code == 'tickets');
    expect(blocks, hasLength(1));
    expect(blocks.single.defaultValue, isEmpty);
    expect(
        EmailTemplateModel.substitutionDefinitions['TICKET_ORDER_CREATED']
                ?.any((sub) => sub.code == 'tickets') ??
            false,
        isFalse);
  });

  test('inline event appearance leaves the optional print design unchanged',
      () {
    final feature = <String, dynamic>{
      'code': 'ticket',
      'is_enabled': true,
      'delivery_mode': 'inline_qr',
      'layout': {
        'schemaVersion': 3,
        'templates': {
          'wide': {'fontId': 'custom-print-font'}
        }
      }
    };
    final original = jsonEncode(feature);
    final draft = <String, dynamic>{
      'ticketDraft': feature,
      'formDraft': <String, dynamic>{'data': <String, dynamic>{}}
    };
    OccasionSetupAppearance.apply(
        draft, Map.of(OccasionSetupAppearance.presets.first));
    expect(jsonEncode(draft['ticketDraft']), original);
    expect((draft['formDraft'] as Map)['data']['design'], isNotNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'disabled setup tickets show confirmation only and preserve inline choice',
      (tester) async {
    final draft = <String, dynamic>{
      'id': 'disabled',
      'eventKind': 'concert',
      'ticketDraft': <String, dynamic>{
        'code': 'ticket',
        'is_enabled': false,
        'delivery_mode': 'inline_qr'
      },
      'formDraft': <String, dynamic>{'data': <String, dynamic>{}}
    };
    final requests = <Map<String, dynamic>>[];
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: OccasionSetupCommunicationSettings(
                        draft: draft,
                        onChanged: (_) => fail('Unexpected write'),
                        loadPreview: (snapshot) async {
                          requests.add(snapshot);
                          return {
                            'subject': 'confirmation',
                            'html': '<p>Confirmation</p>'
                          };
                        })))));
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single['previewMessageType'], isNull);
    expect((draft['ticketDraft'] as Map)['delivery_mode'], 'inline_qr');
    expect(find.text('Náhled e-mailu se vstupenkami'), findsNothing);
  });
}
