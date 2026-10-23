import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/email_templates.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_communication.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_delivery_selector.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_delivery_preview.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_email_preview.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class _NoPdfService extends TicketLayoutService {
  int calls = 0;
  @override
  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background,
      {bool borrowResourcesOnly = false, bool readOnly = false}) async {
    calls++;
    throw StateError('Inline must not request PDF resources');
  }
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_DELIVERY')) {
      await (FontLoader('Futura')
            ..addFont(rootBundle.load('fonts/Futura PT Book.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });

  test('closed delivery mode defaults only when absent and preserves layout',
      () {
    expect(TicketFeature.fromJson({'code': 'ticket'}).deliveryMode,
        TicketDeliveryMode.pdfAttachment);
    for (final mode in TicketDeliveryMode.values) {
      final feature = TicketFeature.fromJson({
        'code': 'ticket',
        'is_enabled': false,
        'delivery_mode': mode.value,
        'layout': {'schemaVersion': 3, 'templates': {}}
      });
      final copy = TicketFeature.fromJson(feature.toJson());
      expect(copy.deliveryMode, mode);
      expect(copy.isEnabled, isFalse);
      expect(copy.layout, feature.layout);
    }
    for (final invalid in [null, '', 'qr', 1]) {
      expect(
          () => TicketFeature.fromJson(
              {'code': 'ticket', 'delivery_mode': invalid}),
          throwsFormatException);
    }
  });

  test(
      'reserved block is rich nonrepeatable body content without fake QR defaults',
      () {
    final block = EmailTemplateModel
        .substitutionDefinitions['TICKET_ORDER_PAYMENT_DONE']!
        .singleWhere((sub) => sub.code == 'tickets');
    expect(block.defaultValue, isEmpty);
    expect(block.kind, EmailValueKind.richBlock);
    expect(block.definition.repeatable, isFalse);
    expect(block.supportsField(EmailTargetField.subject), isFalse);
    expect(
        EmailTemplateModel.substitutionDefinitions['TICKET_ORDER_CONFIRMATION']!
            .any((sub) => sub.code == 'tickets'),
        isFalse);
  });

  test(
      'preview only projects trusted sample PNGs and removes template resources',
      () {
    final png = base64Encode([137, 80, 78, 71, 13, 10, 26, 10, 0]);
    final safe = TicketEmailPreview.safeHtml(
        '<p onclick="bad()" style="background:url(https://bad)">Text</p>'
        '<img src="cid:sample"><img src="https://bad/a.png">'
        '<img src="data:image/png;base64,$png"><script>bad()</script>',
        [
          {'contentId': 'sample', 'content': png}
        ]);
    expect('data:image/png'.allMatches(safe).length, 1);
    expect(safe, isNot(contains('https:')));
    expect(safe, isNot(contains('onclick')));
    expect(safe, isNot(contains('script')));
  });

  test('inline event appearance preserves saved PDF design', () {
    final feature = {
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
    final before = jsonEncode(feature);
    final draft = <String, dynamic>{
      'ticketDraft': feature,
      'formDraft': <String, dynamic>{'data': <String, dynamic>{}}
    };
    OccasionSetupAppearance.apply(
        draft, Map.of(OccasionSetupAppearance.presets.first));
    expect(jsonEncode(draft['ticketDraft']), before);
  });

  testWidgetsWithEnvironment(() => environment,
      'read-only inline settings never load PDF and cannot change mode',
      (tester) async {
    final service = _NoPdfService();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: TicketSettings(
                        feature: TicketFeature(
                            code: 'ticket',
                            isEnabled: true,
                            deliveryMode: TicketDeliveryMode.inlineQr),
                        occasionId: 0,
                        service: service,
                        readOnly: true,
                        showScanningSettings: false)))));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(
        tester
            .widget<DropdownButtonFormField<TicketDeliveryMode>>(
                find.byType(DropdownButtonFormField<TicketDeliveryMode>))
            .onChanged,
        isNull);
    expect(find.text('Upravit PDF pro tisk'), findsOneWidget);
  });

  for (final enabled in [true, false]) {
    testWidgetsWithEnvironment(() => environment,
        'setup preview retains template catalog and enabled=$enabled mode',
        (tester) async {
      final draft = <String, dynamic>{
        'formEnabled': true,
        'communicationTone': 'inherit',
        'ticketDraft': <String, dynamic>{
          'code': 'ticket',
          'is_enabled': enabled,
          'layout': {'schemaVersion': 3, 'templates': {}}
        },
        'emailTemplateOverrides': {
          'TICKET_ORDER_PAYMENT_DONE': {
            'subject': 'Custom',
            'html': '<p>Keep</p>'
          }
        },
        'formDraft': <String, dynamic>{
          'fields': [
            {'type': 'ticket'}
          ],
          'data': <String, dynamic>{}
        }
      };
      final requests = <Map<String, dynamic>>[];
      await environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: StatefulBuilder(
                          builder: (context, setState) =>
                              OccasionSetupCommunication(
                                  draftId: 'test',
                                  data: draft,
                                  loader: () async => {'defaults': {}},
                                  onChanged: (patch) =>
                                      setState(() => draft.addAll(patch)),
                                  loadPreview: (snapshot) async {
                                    requests.add(snapshot);
                                    return {
                                      'subject': 'Sample',
                                      'html': '<p>Sample</p>',
                                      'emailTemplates': [],
                                      'emailScope': {
                                        'unit': {'id': 1},
                                        'organization': {'id': 2}
                                      }
                                    };
                                  }))))));
      await tester.pumpAndSettle();
      expect(requests.any((s) => s['previewMessageType'] == null), isTrue);
      expect(requests.any((s) => s['previewMessageType'] == 'order_tickets'),
          isFalse);
      expect(find.byType(TicketEmailPreview), findsNothing);
      if (enabled) {
        final selector = tester.widget<TicketDeliverySelector>(
            find.byType(TicketDeliverySelector));
        selector.onChanged(TicketDeliveryMode.inlineQr);
        await tester.pumpAndSettle();
        expect((draft['ticketDraft'] as Map)['delivery_mode'], 'inline_qr');
        expect((draft['ticketDraft'] as Map)['layout'], isNotNull);
        expect(requests.any((s) => s['previewMessageType'] == 'order_tickets'),
            isFalse);
        await tester.ensureVisible(find.byType(TicketDeliveryPreview));
        await tester.tap(find.descendant(
            of: find.byType(TicketDeliveryPreview),
            matching: find.byType(TextButton)));
        await tester.pumpAndSettle();
        expect(find.byType(AppAlertDialog), findsOneWidget);
        expect(requests.last['previewMessageType'], 'order_tickets');
        expect((requests.last['ticketDraft'] as Map)['delivery_mode'],
            'inline_qr');
      }
      expect(draft.containsKey('previewMessageType'), isFalse);
      expect(
          (draft['emailTemplateOverrides'] as Map)['TICKET_ORDER_PAYMENT_DONE']
              ['subject'],
          'Custom');
    });
  }
  testWidgetsWithEnvironment(() => environment,
      'open preview discards stale revision and retries failed loading',
      (tester) async {
    var revision = 0;
    late StateSetter update;
    final first = Completer<Map<String, dynamic>>();
    final current = Completer<Map<String, dynamic>>();
    var calls = 0;
    await environment.pumpWidget(tester, MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return TicketDeliveryPreview(
          revision: revision,
          load: (_) {
            calls++;
            if (calls == 1) return first.future;
            if (calls == 2) return current.future;
            return Future.value(
                {'subject': 'Retry result', 'html': '<p>OK</p>'});
          });
    }))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    update(() => revision++);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 2);
    current.completeError(StateError('Preview unavailable'));
    await tester.pumpAndSettle();
    first.complete({'subject': 'Stale', 'html': '<p>Old</p>'});
    await tester.pumpAndSettle();
    expect(find.text('Stale'), findsNothing);
    expect(find.text('Náhled se nepodařilo načíst.'), findsOneWidget);
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(find.text('Retry result'), findsOneWidget);
  });

  for (final width in [390.0, 1200.0]) {
    testWidgetsWithEnvironment(() => environment,
        'compact delivery controls and dialog fit width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var mode = TicketDeliveryMode.both;
      var calls = 0;
      await environment.pumpWidget(
          tester,
          MaterialApp(
              theme: ThemeConfig.theme(),
              home: Scaffold(
                  body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: StatefulBuilder(
                          builder: (context, update) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TicketDeliverySelector(
                                        value: mode,
                                        enabled: true,
                                        onChanged: (value) =>
                                            update(() => mode = value)),
                                    TicketDeliveryPreview(
                                        revision: mode,
                                        load: (count) async {
                                          calls++;
                                          return {
                                            'subject': 'Vaše vstupenky',
                                            'html':
                                                '<h2>Vaše vstupenka</h2><p>U vstupu ukažte tento QR kód.</p>',
                                            'attachments': [
                                              {
                                                'filename':
                                                    'vstupenka-ukazka-1.pdf'
                                              }
                                            ]
                                          };
                                        }),
                                  ]))))));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester
          .tap(find.byType(DropdownButtonFormField<TicketDeliveryMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QR přímo v e-mailu').last);
      await tester.pumpAndSettle();
      expect(mode, TicketDeliveryMode.inlineQr);
      expect(calls, 0);
      expect(tester.getSize(find.byType(TicketDeliverySelector)).height,
          lessThan(150));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
      const capture = bool.fromEnvironment('CAPTURE_DELIVERY');
      if (capture) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                '/tmp/ticket-delivery-settings-${width.toInt()}.png'));
      }
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      if (capture) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                '/tmp/ticket-delivery-dialog-${width.toInt()}.png'));
      }
      await tester.tap(find.text('3 vstupenky'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(TicketEmailPreview), findsNothing);
    });
  }
}
