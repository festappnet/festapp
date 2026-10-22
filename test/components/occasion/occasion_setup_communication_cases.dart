import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_communication.dart';
import 'dart:async';
import 'package:fstapp/components/occasion/setup/occasion_setup_email_preview.dart';

import '../../support/fixtures/localization_log_fixture.dart';

Map<String, dynamic> _draft({bool paid = true}) => {
      'formEnabled': true,
      'formDraft': {
        'data': <String, dynamic>{'unrelated': 'keep'},
        'fields': [
          {
            'type': 'product_type',
            'product_type_data': {
              'products': [
                {'id': 1, 'price': paid ? 100 : 0, 'currency_code': 'CZK'},
              ],
            },
          },
        ],
      },
      'replyToMode': 'inherit',
      'replyToEmail': '',
      'communicationTone': 'inherit',
      'remindersMode': 'inherit',
      'reminderLeadDays': '',
    };

Map<String, dynamic> _metadata(Map<String, dynamic> draft) =>
    (draft['formDraft'] as Map)['data'] as Map<String, dynamic>;

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  test('inherit removes overrides and preserves unrelated form metadata', () {
    final draft = _draft();
    _metadata(draft).addAll({
      'communication_tone': 'informal',
      'is_reminder_enabled': false,
      'reminder_interval_seconds': 172800,
    });
    serializeCommunicationDraft(draft);
    expect(_metadata(draft), {'unrelated': 'keep'});
  });

  test('explicit values serialize semantically; free forms omit reminders', () {
    final draft = _draft()
      ..addAll({
        'communicationTone': 'formal',
        'remindersMode': 'disabled',
        'reminderLeadDays': '1,5',
      });
    serializeCommunicationDraft(draft);
    expect(_metadata(draft)['communication_tone'], 'formal');
    expect(_metadata(draft)['is_reminder_enabled'], false);
    expect(_metadata(draft)['reminder_interval_seconds'], 129600);
    draft['formDraft'] = _draft(paid: false)['formDraft'];
    serializeCommunicationDraft(draft);
    expect(_metadata(draft), {
      'unrelated': 'keep',
      'communication_tone': 'formal',
    });
  });

  test(
    'initialization preserves saved choices and resets from adopted form',
    () {
      final draft = _draft()..['communicationTone'] = 'informal';
      _metadata(draft).addAll({
        'communication_tone': 'formal',
        'is_reminder_enabled': false,
        'reminder_interval_seconds': 43200,
      });
      initializeCommunicationDraft(draft);
      expect(draft['communicationTone'], 'informal');
      initializeCommunicationDraft(draft, reset: true);
      expect(draft['communicationTone'], 'formal');
      expect(draft['remindersMode'], 'disabled');
      expect(double.parse(draft['reminderLeadDays'] as String), .5);
      _metadata(draft)['is_reminder_enabled'] = true;
      initializeCommunicationDraft(draft, reset: true);
      expect(draft['remindersMode'], 'inherit');
    },
  );

  test(
      'new event inherits organization even when default form disables reminders',
      () {
    final draft = <String, dynamic>{
      'formDefaultsFollowEvent': true,
      'formDraft': {
        'data': {
          'is_reminder_enabled': false,
          'reminder_interval_seconds': 43200,
          'communication_tone': 'formal',
        }
      },
    };
    initializeCommunicationDraft(draft, reset: true);
    expect(draft['remindersMode'], 'inherit');
    expect(draft['reminderLeadDays'], '');
    expect(draft['replyToMode'], 'inherit');
    expect(draft['communicationTone'], 'inherit');
    draft['remindersMode'] = 'disabled';
    initializeCommunicationDraft(draft);
    expect(draft['remindersMode'], 'disabled');
  });

  test('custom reply address and paid reminder lead must be valid', () {
    final draft = _draft()..['replyToMode'] = 'custom';
    for (final email in ['', '   ', 'invalid', 'missing@']) {
      draft['replyToEmail'] = email;
      expect(communicationDraftValid(draft), isFalse, reason: email);
    }
    draft['replyToEmail'] = ' office@example.org ';
    expect(communicationDraftValid(draft), isTrue);
    for (final lead in ['-1', 'NaN', 'Infinity', 'tomorrow']) {
      draft['reminderLeadDays'] = lead;
      expect(communicationDraftValid(draft), isFalse, reason: lead);
    }
    for (final lead in ['', '0', '0,5']) {
      draft['reminderLeadDays'] = lead;
      expect(communicationDraftValid(draft), isTrue, reason: lead);
    }
    draft['formDraft'] = _draft(paid: false)['formDraft'];
    draft['reminderLeadDays'] = '-1';
    expect(communicationDraftValid(draft), isTrue);
  });

  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> data, {
    required bool manager,
    bool firstEvent = true,
    bool paymentTiming = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                return OccasionSetupCommunication(
                  draftId: 'draft',
                  paymentTiming: paymentTiming,
                  data: data,
                  onChanged: (patch) => setState(() => data.addAll(patch)),
                  loader: () async => {
                    'canManage': manager,
                    'firstEvent': firstEvent,
                    'defaults': {
                      'replyTo': 'organization@example.org',
                      'tone': 'formal',
                      'remindersEnabled': true,
                      'leadSeconds': 86400,
                    },
                    'unit': {
                      'id': 7,
                      'aggregate_version': 9,
                      'data': {
                        'unrelated': 'preserved',
                        'reply_to': 'original@example.org',
                        'communication_tone': 'formal',
                        'is_reminder_enabled': true,
                        'reminder_interval_seconds': 86400,
                      },
                    },
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('inherited reply choice names the organization address',
      (tester) async {
    final data = _draft();
    await mount(tester, data, manager: false);
    expect(
        find.text(
            'OccasionSetup.setupDetails.inheritOrganization: organization@example.org'),
        findsWidgets);
    expect(data['replyToMode'], 'inherit');
  });

  test(
    'each question validates only its own inputs; review validates both',
    () {
      final data = _draft()
        ..addAll({
          'replyToMode': 'custom',
          'replyToEmail': 'invalid',
          'reminderLeadDays': '2',
        });
      expect(communicationDraftValid(data, includeReply: false), isTrue);
      expect(communicationDraftValid(data, includeReminders: false), isFalse);
      expect(communicationDraftValid(data), isFalse);
      data['replyToEmail'] = 'valid@example.org';
      data['reminderLeadDays'] = '-1';
      expect(communicationDraftValid(data, includeReply: false), isFalse);
      expect(communicationDraftValid(data, includeReminders: false), isTrue);
      expect(communicationDraftValid(data), isFalse);
    },
  );

  testWidgets(
    'editor can change this event but cannot save organization defaults',
    (tester) async {
      final data = _draft(paid: false)
        ..addAll({'replyToMode': 'custom', 'replyToEmail': 'old@example.org'});
      await mount(
        tester,
        data,
        manager: false,
      );
      expect(
        find.byWidgetPredicate((widget) => widget is OutlinedButton),
        findsNothing,
      );
      expect(
        find.text('OccasionSetup.setupDetails.paymentReminders'),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('communication-reply')),
        'new@example.org',
      );
      await tester.pump();
      expect(data['replyToEmail'], 'new@example.org');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager edits event without organization save action',
      (tester) async {
    final data = _draft();
    await mount(tester, data, manager: true, paymentTiming: true);
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(data['remindersMode'], 'disabled');
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview ignores stale completion after draft change',
      (tester) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    var calls = 0;
    final data = <String, dynamic>{'title': 'first'};
    Future<Map<String, dynamic>> load(Map<String, dynamic> snapshot) {
      calls++;
      expect(snapshot['title'], calls == 1 ? 'first' : 'second');
      snapshot['title'] = 'detached';
      return calls == 1 ? first.future : second.future;
    }

    Widget view() => MaterialApp(
        home: Scaffold(
            body: OccasionSetupEmailPreview(draft: data, loadPreview: load)));
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 301));
    expect(data['title'], 'first');
    data['title'] = 'second';
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 301));
    second.complete({'subject': 'current', 'html': '<p>Current preview</p>'});
    await tester.pumpAndSettle();
    first.complete({'subject': 'stale', 'html': '<p>Stale preview</p>'});
    await tester.pumpAndSettle();
    expect(find.text('current'), findsOneWidget);
    expect(find.text('stale'), findsNothing);
    expect(data['title'], 'second');
    expect(tester.takeException(), isNull);
  });
}
