import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/bank_accounts/views/bank_sync_email_queue.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_connection_tab.dart';
import 'package:festapp_core/eshop.dart';
import 'package:festapp_core/time.dart' as timezone_data;

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

final _observation = <String, dynamic>{
  'delivery_id': 'delivery',
  'body_sha256': 'hash',
  'facts': {
    'amount_cents': 10000,
    'currency': 'CZK',
    'raw_vs': '1007',
    'counter_account': '222/2010',
    'sender_name': 'Jane Smith',
    'date': '2026-11-22T12:00:00Z',
    'message': 'Tickets',
  },
  'candidates': [
    {
      'payment_info_id': 17,
      'order_id': 42,
      'order_symbol': 'ORDER42',
      'order_number': 42,
      'state': 'ordered',
      'customer_name': 'Jane Smith',
      'customer_email': 'jane@example.invalid',
      'remaining_due': 100,
      'amount_matches': true,
    },
  ],
};

Future<void> _pump(WidgetTester tester, Widget child) async {
  await EasyLocalization.ensureInitialized();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'unused',
      startLocale: const Locale('en'),
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          builder: DependencyMaterialBridge.builder,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: [
            ...context.localizationDelegates,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    timezone_data.OccasionTimeContext.initializeTimeZones();
  });

  testWidgets('email connection shows confirmation notice to readonly users', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      BankAccountConnectionTab(
        account: BankAccountModel.fromJson({
          'id': 1,
          'bank_sync': {'mode': 'email', 'state': 'connected'},
        }),
        isReadOnly: true,
        isFio: false,
        isSaving: false,
        pairingCode: null,
        onRegenerateToken: () {},
        tokenController: controller,
        expiryDate: null,
        onExpiryDateChanged: (_) {},
        onSaveToken: () {},
      ),
    );
    expect(find.text(BankAccountStrings.emailIdentityNotice), findsOneWidget);
    expect(
      find.text(BankAccountStrings.emailConfirmationRequired),
      findsOneWidget,
    );
    expect(find.text(BankAccountStrings.emailConfirm), findsNothing);
  });

  testWidgets(
    'exact email duplicate offers dismissal without separate payment attestation',
    (tester) async {
      await _pump(
        tester,
        BankSyncEmailQueue(
          loadPage: (_) async => {
            'items': [
              {..._observation, 'exact_duplicate': true},
            ],
            'next_cursor': null,
          },
          readOnly: false,
          confirm: (_, _, {bool notDuplicate = false}) async =>
              throw StateError('Exact duplicate must not request confirmation'),
          dismiss: (_, _) async {},
        ),
      );
      expect(find.text(BankAccountStrings.emailExactDuplicate), findsOneWidget);
      expect(find.text(BankAccountStrings.emailConfirm), findsNothing);
      expect(find.text(BankAccountStrings.emailNotDuplicate), findsNothing);
      expect(find.text(BankAccountStrings.emailDismiss), findsOneWidget);
    },
  );

  testWidgets('email queue displays bank facts and candidate order', (
    tester,
  ) async {
    await _pump(
      tester,
      BankSyncEmailQueue(
        loadPage: (_) async => {
          'items': [_observation],
          'next_cursor': null,
        },
        confirm: (_, _, {bool notDuplicate = false}) async => {
          'action': 'confirmed',
          'transaction_paired': true,
        },
        readOnly: false,
      ),
    );
    expect(find.textContaining('Jane Smith'), findsOneWidget);
    await tester.tap(find.text(BankAccountStrings.emailConfirm));
    await tester.pumpAndSettle();
    expect(find.textContaining('42'), findsOneWidget);
    expect(
      find.textContaining(BankAccountStrings.emailOrderState('ordered')),
      findsOneWidget,
    );
    expect(
      find.textContaining(BankAccountStrings.emailAmountMatches),
      findsOneWidget,
    );
  });

  testWidgets('email confirmation requires candidate and banking attestation', (
    tester,
  ) async {
    int? confirmed;
    await _pump(
      tester,
      BankSyncEmailQueue(
        loadPage: (_) async => {
          'items': confirmed == null ? [_observation] : [],
          'next_cursor': null,
        },
        confirm: (_, payment, {bool notDuplicate = false}) async {
          confirmed = payment;
          return {'action': 'confirmed', 'transaction_paired': true};
        },
        readOnly: false,
      ),
    );
    await tester.tap(find.text(BankAccountStrings.emailConfirm));
    await tester.pumpAndSettle();
    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(RadioListTile<int>));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(confirmed, 17);
    expect(find.text(BankAccountStrings.emailOutcomeConfirmed), findsOneWidget);
    expect(find.text(BankAccountStrings.emailQueueEmpty), findsOneWidget);
  });

  testWidgets('readonly email queue has no confirmation action', (
    tester,
  ) async {
    await _pump(
      tester,
      BankSyncEmailQueue(
        loadPage: (_) async => {
          'items': [_observation],
          'next_cursor': null,
        },
        confirm: (_, _, {bool notDuplicate = false}) async {
          fail('readonly confirmation');
        },
        readOnly: true,
      ),
    );
    expect(find.textContaining('Jane Smith'), findsOneWidget);
    expect(find.text(BankAccountStrings.emailConfirm), findsNothing);
  });

  testWidgets('email lookup shows the server selected customer and order', (
    tester,
  ) async {
    String? searched;
    await _pump(
      tester,
      BankSyncEmailQueue(
        loadPage: (_) async => {
          'items': [_observation],
          'next_cursor': null,
        },
        readOnly: false,
        confirm: (_, _, {bool notDuplicate = false}) async => {
          'action': 'confirmed',
          'transaction_paired': true,
        },
        lookup: (facts, query) async {
          searched = query;
          return [
            {
              'payment_info_id': 18,
              'order_id': 999,
              'order_symbol': 'TICKETS73',
              'state': 'ordered',
              'customer_name': 'Alice Brown',
              'customer_email': 'alice@example.invalid',
              'remaining_due': 100,
              'amount_matches': true,
            },
          ];
        },
      ),
    );
    await tester.tap(find.text(BankAccountStrings.emailConfirm));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'RF18539007547034');
    await tester.tap(find.text(BankAccountStrings.emailLookup));
    await tester.pumpAndSettle();
    expect(searched, 'RF18539007547034');
    expect(find.textContaining('TICKETS73'), findsOneWidget);
    expect(find.textContaining('alice@example.invalid'), findsOneWidget);
    expect(find.textContaining('ORDER42'), findsNothing);
  });

  testWidgets('email dismissal requires a reason and refreshes the queue', (
    tester,
  ) async {
    String? reason;
    await _pump(
      tester,
      BankSyncEmailQueue(
        loadPage: (_) async => {
          'items': reason == null ? [_observation] : [],
          'next_cursor': null,
        },
        readOnly: false,
        confirm: (_, _, {bool notDuplicate = false}) async => {
          'action': 'confirmed',
          'transaction_paired': true,
        },
        dismiss: (row, value) async => reason = value,
      ),
    );
    await tester.tap(find.text(BankAccountStrings.emailDismiss));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField),
      'No matching receipt in internet banking',
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(reason, 'No matching receipt in internet banking');
    expect(find.text(BankAccountStrings.emailQueueEmpty), findsOneWidget);
  });

  testWidgets('email queue load more uses the returned cursor', (tester) async {
    Map<String, dynamic>? requested;
    final cursor = <String, dynamic>{
      'received_at': '2026-11-22T00:00:00Z',
      'delivery_id': 'delivery',
    };
    await _pump(
      tester,
      BankSyncEmailQueue(
        readOnly: false,
        confirm: (_, _, {bool notDuplicate = false}) async => {
          'action': 'confirmed',
          'transaction_paired': true,
        },
        loadPage: (after) async {
          requested = after;
          return {
            'items': [
              after == null
                  ? _observation
                  : {
                      ..._observation,
                      'delivery_id': 'second',
                      'facts': {
                        ...(_observation['facts'] as Map),
                        'sender_name': 'Second sender',
                      },
                    },
            ],
            'next_cursor': after == null ? cursor : null,
          };
        },
      ),
    );
    await tester.tap(find.text(BankAccountStrings.emailLoadMore));
    await tester.pumpAndSettle();
    expect(requested, cursor);
    expect(find.textContaining('Second sender'), findsOneWidget);
    expect(find.text(BankAccountStrings.emailLoadMore), findsNothing);
  });

  testWidgets(
    'possible_duplicate outcome stays open, shows related tx, and requires separate-payment attestation',
    (tester) async {
      final calls = <bool>[];
      var paired = false;
      final duplicateRow = <String, dynamic>{
        'transaction_id': 91,
        'ingest_source': 'banksync_email_confirmed',
        'transaction_paired': true,
        'order_symbol': 'PAID91',
        'facts': {
          'amount_cents': 10000,
          'currency': 'CZK',
          'date': '2026-11-22T12:00:00Z',
          'raw_vs': '1007',
        },
      };
      await _pump(
        tester,
        BankSyncEmailQueue(
          loadPage: (_) async => {
            'items': paired ? [] : [_observation],
            'next_cursor': null,
          },
          readOnly: false,
          confirm: (_, _, {bool notDuplicate = false}) async {
            calls.add(notDuplicate);
            if (!notDuplicate) {
              return {
                'action': 'possible_duplicate',
                'transaction_paired': false,
                'possible_duplicates': [duplicateRow],
              };
            }
            paired = true;
            return {'action': 'confirmed', 'transaction_paired': true};
          },
        ),
      );
      await tester.tap(find.text(BankAccountStrings.emailConfirm));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RadioListTile<int>));
      await tester.tap(
        find.byKey(const ValueKey('email-attestation-checkbox')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Dialog stays open, never shows success, displays the related tx and new checkbox.
      expect(calls, [false]);
      expect(find.text(BankAccountStrings.emailOutcomeConfirmed), findsNothing);
      expect(
        find.text(BankAccountStrings.emailOutcomePossibleDuplicate),
        findsOneWidget,
      );
      expect(find.textContaining('PAID91'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('email-not-duplicate-checkbox')),
      );
      await tester.tap(
        find.byKey(const ValueKey('email-not-duplicate-checkbox')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(calls, [false, true]);
      expect(
        find.text(BankAccountStrings.emailOutcomeConfirmed),
        findsOneWidget,
      );
      expect(find.text(BankAccountStrings.emailQueueEmpty), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate_of outcome distinguishes paired vs unpaired existing transaction and never shows paired success',
    (tester) async {
      for (final existingPaired in [true, false]) {
        var resolved = false;
        await _pump(
          tester,
          BankSyncEmailQueue(
            key: ValueKey('duplicate-$existingPaired'),
            loadPage: (_) async => {
              'items': resolved ? [] : [_observation],
              'next_cursor': null,
            },
            readOnly: false,
            confirm: (_, _, {bool notDuplicate = false}) async {
              resolved = true;
              return {
                'action': 'duplicate_of',
                'transaction_id': 77,
                'transaction_paired': existingPaired,
              };
            },
          ),
        );
        await tester.tap(find.text(BankAccountStrings.emailConfirm));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(RadioListTile<int>));
        await tester.tap(
          find.byKey(const ValueKey('email-attestation-checkbox')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(
          find.text(BankAccountStrings.emailOutcomeConfirmed),
          findsNothing,
        );
        expect(
          find.text(
            existingPaired
                ? BankAccountStrings.emailOutcomeDuplicatePaired
                : BankAccountStrings.emailOutcomeDuplicateUnpaired,
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'degraded email connection preserves status beside confirmation notice',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        BankAccountConnectionTab(
          account: BankAccountModel.fromJson({
            'id': 1,
            'bank_sync': {'mode': 'email', 'state': 'degraded'},
          }),
          isReadOnly: true,
          isFio: false,
          isSaving: false,
          pairingCode: null,
          onRegenerateToken: () {},
          tokenController: controller,
          expiryDate: null,
          onExpiryDateChanged: (_) {},
          onSaveToken: () {},
        ),
      );
      expect(
        find.text(BankAccountStrings.connectionStatus('degraded')),
        findsOneWidget,
      );
      expect(
        find.text(BankAccountStrings.emailConfirmationRequired),
        findsOneWidget,
      );
    },
  );
}
