import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_communication.dart';
import 'package:fstapp/components/unit/unit_model.dart';

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
    required Future<UnitModel> Function(UnitModel) save,
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
                  saveDefaults: save,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final paymentTiming in [false, true]) {
    testWidgets(
      'manager saves only visible defaults with CAS: timing=$paymentTiming',
      (tester) async {
        final data = _draft()
          ..addAll({
            'replyToMode': 'custom',
            'replyToEmail': 'events@example.org',
            'communicationTone': 'informal',
            'remindersMode': 'disabled',
            'reminderLeadDays': '2',
          });
        final saved = <UnitModel>[];
        await mount(
          tester,
          data,
          manager: true,
          paymentTiming: paymentTiming,
          save: (unit) async {
            saved.add(unit);
            return unit;
          },
        );
        expect(saved, isEmpty);
        expect(
          find.text('OccasionSetup.setupDetails.firstEventDefaultsHint'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byWidgetPredicate((widget) => widget is OutlinedButton),
        );
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is OutlinedButton),
        );
        await tester.pumpAndSettle();
        expect(saved, hasLength(1));
        expect(saved.single.id, 7);
        expect(saved.single.aggregateVersion, 9);
        expect(saved.single.data, {
          'unrelated': 'preserved',
          'reply_to':
              paymentTiming ? 'original@example.org' : 'events@example.org',
          'communication_tone': paymentTiming ? 'formal' : 'informal',
          'is_reminder_enabled': !paymentTiming,
          'reminder_interval_seconds': paymentTiming ? 172800 : 86400,
        });
        expect(data['replyToMode'], paymentTiming ? 'custom' : 'inherit');
        expect(
          data['communicationTone'],
          paymentTiming ? 'informal' : 'inherit',
        );
        expect(data['remindersMode'], paymentTiming ? 'inherit' : 'disabled');
        expect(data['reminderLeadDays'], paymentTiming ? '' : '2');
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      var saves = 0;
      await mount(
        tester,
        data,
        manager: false,
        save: (unit) async {
          saves++;
          return unit;
        },
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
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed organization save retains event overrides for retry', (
    tester,
  ) async {
    final data = _draft()..['communicationTone'] = 'informal';
    await mount(
      tester,
      data,
      manager: true,
      save: (_) async => throw StateError('revision conflict'),
    );
    await tester.ensureVisible(
      find.byWidgetPredicate((widget) => widget is OutlinedButton),
    );
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is OutlinedButton),
    );
    await tester.pumpAndSettle();
    expect(data['communicationTone'], 'informal');
    expect(
      find.text('OccasionSetup.setupDetails.organizationDefaultsFailed'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
