import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
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
      jsonDecode(
        File('assets/translations/${locale.languageCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
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

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await EasyLocalization.ensureInitialized();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: [locale],
      path: 'unused',
      startLocale: locale,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          builder: (context, child) => DependencyMaterialBridge.builder(
            context,
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
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

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, [
  Map<String, dynamic>? cursor,
]) => {'items': items, 'next_cursor': cursor};

BankSyncEmailQueue _queue({
  Map<String, dynamic>? observation,
  bool readOnly = false,
  bool compact = false,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>?)? loadPage,
  ConfirmBankEmail? confirm,
  Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>, String)?
  lookup,
  Future<void> Function(Map<String, dynamic>, String)? dismiss,
}) => BankSyncEmailQueue(
  loadPage: loadPage ?? (_) async => _page([observation ?? _observation]),
  confirm:
      confirm ??
      (_, _, {bool notDuplicate = false}) async =>
          fail('unexpected confirmation'),
  lookup: lookup,
  dismiss: dismiss,
  readOnly: readOnly,
  compact: compact,
);

const _confirmed = {'action': 'confirmed', 'transaction_paired': true};
final _candidate = find.byType(RadioListTile<int>);
final _attestation = find.byKey(const ValueKey('email-attestation-checkbox'));
final _separate = find.byKey(const ValueKey('email-not-duplicate-checkbox'));
final _submit = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(FilledButton),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _canSubmit(WidgetTester tester) =>
    tester.widget<FilledButton>(_submit).onPressed != null;

Future<void> _connection(WidgetTester tester, String state) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await _pump(
    tester,
    BankAccountConnectionTab(
      account: BankAccountModel.fromJson({
        'id': 1,
        'bank_sync': {'mode': 'email', 'state': state},
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    timezone_data.OccasionTimeContext.initializeTimeZones();
  });

  testWidgets(
    'queue dialogs stay above the routed bank account and return focus',
    (tester) async {
      var closes = 0;
      var attempts = 0;
      String? reason;
      await _pump(
        tester,
        RoutedBankAccountDialog(
          title: 'Účet pro vstupenky',
          onClose: () => closes++,
          child: SingleChildScrollView(
            child: _queue(
              observation: _observation,
              confirm: (_, _, {bool notDuplicate = false}) async {
                attempts++;
                if (attempts == 1) throw StateError('Fixture command failure');
                return _confirmed;
              },
              dismiss: (_, value) async => reason = value,
            ),
          ),
        ),
        locale: const Locale('cs'),
      );

      final root = tester.state<NavigatorState>(find.byType(Navigator).first);
      final confirm = find.text(BankAccountStrings.emailConfirm);
      final confirmButton = find.ancestor(
        of: confirm,
        matching: find.byType(FilledButton),
      );
      final buttonContext = tester.element(confirmButton);
      final account = Navigator.of(buttonContext);
      expect(account, isNot(same(root)));
      Focus.of(tester.element(confirm)).requestFocus();
      await tester.pump();
      final originalFocus = FocusManager.instance.primaryFocus;
      await _tap(tester, confirm);
      final dialog = find.byType(AlertDialog);
      expect(Navigator.of(tester.element(dialog)), same(account));
      expect(FocusManager.instance.primaryFocus, isNot(same(originalFocus)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(closes, 0);
      expect(FocusManager.instance.primaryFocus, same(originalFocus));

      await _tap(tester, confirm);
      await _tap(tester, _candidate);
      await _tap(tester, _attestation);
      await _tap(tester, _submit);
      expect(attempts, 1);
      expect(dialog, findsOneWidget);
      expect(_canSubmit(tester), isTrue);
      await _tap(tester, _submit);
      expect(attempts, 2);
      expect(dialog, findsNothing);
      expect(closes, 0);

      final dismiss = find.text(BankAccountStrings.emailDismiss);
      await _tap(tester, dismiss);
      expect(Navigator.of(tester.element(dialog)), same(account));
      await _tap(
        tester,
        find.descendant(of: dialog, matching: find.text(CommonStrings.cancel)),
      );
      expect(reason, isNull);
      expect(dialog, findsNothing);
      await _tap(tester, dismiss);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(closes, 0);
      await _tap(tester, dismiss);
      await tester.enterText(
        find.byType(TextField),
        'Platba není v bankovnictví',
      );
      await tester.pump();
      await _tap(tester, _submit);
      expect(reason, 'Platba není v bankovnictví');
      expect(closes, 0);
    },
  );

  for (final (width, scale) in [(320.0, 1.6), (600.0, 1.0)]) {
    testWidgets(
      'queue cards and actions fit a ${width}px Czech panel at ${scale}x',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(
          tester,
          SingleChildScrollView(child: _queue(dismiss: (_, _) async {})),
          locale: const Locale('cs'),
          textScale: scale,
        );
        final card = tester.getRect(find.byType(Card));
        final confirm = tester.getRect(
          find.text(BankAccountStrings.emailConfirm),
        );
        final dismiss = tester.getRect(
          find.text(BankAccountStrings.emailDismiss),
        );
        expect(card.width, greaterThan(width - 12));
        expect(card.contains(confirm.center), isTrue);
        expect(card.contains(dismiss.center), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('email connection shows confirmation notice to readonly users', (
    tester,
  ) async {
    await _connection(tester, 'connected');
    expect(find.text(BankAccountStrings.emailIdentityNotice), findsOneWidget);
    expect(
      find.text(BankAccountStrings.emailConfirmationRequired),
      findsOneWidget,
    );
    expect(find.text(BankAccountStrings.emailConfirm), findsNothing);
  });

  testWidgets(
    'restricted possible duplicate stays reviewable without exposing bank details',
    (tester) async {
      await _pump(
        tester,
        _queue(
          observation: {
            ..._observation,
            'possible_duplicates': [
              {'restricted': true},
            ],
          },
          dismiss: (_, _) async {},
        ),
      );
      expect(
        find.text(BankAccountStrings.emailDuplicateRestricted),
        findsOneWidget,
      );
      expect(find.text(BankAccountStrings.emailConfirm), findsOneWidget);
      expect(find.text(BankAccountStrings.emailNotDuplicate), findsNothing);
      expect(find.text(BankAccountStrings.emailDismiss), findsOneWidget);
    },
  );

  testWidgets('email queue displays bank facts and candidate order', (
    tester,
  ) async {
    await _pump(tester, _queue());
    expect(find.textContaining('Jane Smith'), findsOneWidget);
    await _tap(tester, find.text(BankAccountStrings.emailConfirm));
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
      _queue(
        loadPage: (_) async => _page(confirmed == null ? [_observation] : []),
        confirm: (_, payment, {bool notDuplicate = false}) async {
          confirmed = payment;
          return _confirmed;
        },
      ),
    );
    await _tap(tester, find.text(BankAccountStrings.emailConfirm));
    expect(_canSubmit(tester), isFalse);
    await _tap(tester, _candidate);
    expect(_canSubmit(tester), isFalse);
    await _tap(tester, _attestation);
    expect(_canSubmit(tester), isTrue);
    await _tap(tester, _submit);
    expect(confirmed, 17);
    expect(find.text(BankAccountStrings.emailOutcomeConfirmed), findsOneWidget);
    expect(find.text(BankAccountStrings.emailQueueEmpty), findsOneWidget);
  });

  testWidgets('readonly email queue has no confirmation action', (
    tester,
  ) async {
    await _pump(tester, _queue(readOnly: true));
    expect(find.textContaining('Jane Smith'), findsOneWidget);
    expect(find.text(BankAccountStrings.emailConfirm), findsNothing);
  });

  testWidgets('email lookup shows the server selected customer and order', (
    tester,
  ) async {
    String? searched;
    await _pump(
      tester,
      _queue(
        lookup: (_, query) async {
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
    await _tap(tester, find.text(BankAccountStrings.emailConfirm));
    await tester.enterText(find.byType(TextField), 'RF18539007547034');
    await _tap(tester, find.text(BankAccountStrings.emailLookup));
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
      _queue(
        compact: true,
        loadPage: (_) async => _page(reason == null ? [_observation] : []),
        dismiss: (_, value) async => reason = value,
      ),
    );
    await _tap(tester, find.text(BankAccountStrings.emailPendingQueueExpand));
    await _tap(tester, find.text(BankAccountStrings.emailDismiss));
    expect(_canSubmit(tester), isFalse);
    await tester.enterText(
      find.byType(TextField),
      'No matching receipt in internet banking',
    );
    await tester.pump();
    await _tap(tester, _submit);
    expect(reason, 'No matching receipt in internet banking');
    expect(find.text(BankAccountStrings.emailQueueEmpty), findsOneWidget);
    final refresh = tester.widget<IconButton>(
      find.byTooltip(CommonStrings.refresh),
    );
    expect(refresh.focusNode!.hasFocus, isTrue);
  });

  testWidgets('email queue load more uses the returned cursor', (tester) async {
    Map<String, dynamic>? requested;
    var loads = 0;
    final cursor = {
      'received_at': '2026-11-22T00:00:00Z',
      'delivery_id': 'delivery',
    };
    await _pump(
      tester,
      _queue(
        compact: true,
        loadPage: (after) async {
          loads++;
          requested = after;
          return after == null
              ? _page([_observation], cursor)
              : _page([
                  {
                    ..._observation,
                    'delivery_id': 'second',
                    'facts': {
                      ...(_observation['facts'] as Map),
                      'sender_name': 'Second sender',
                    },
                  },
                ]);
        },
      ),
    );
    await _tap(tester, find.byType(ExpansionTile));
    expect(loads, 1);
    await _tap(tester, find.text(BankAccountStrings.emailLoadMore));
    expect(requested, cursor);
    expect(find.textContaining('Second sender'), findsOneWidget);
    expect(find.text(BankAccountStrings.emailLoadMore), findsNothing);
  });

  testWidgets(
    'possible_duplicate outcome stays open, shows related tx, and requires separate-payment attestation',
    (tester) async {
      final calls = <bool>[];
      var paired = false;
      await _pump(
        tester,
        _queue(
          loadPage: (_) async => _page(paired ? [] : [_observation]),
          confirm: (row, _, {bool notDuplicate = false}) async {
            calls.add(notDuplicate);
            if (notDuplicate) {
              expect(row['duplicate_review_token'], 'review-token');
              paired = true;
              return _confirmed;
            }
            return {
              'action': 'possible_duplicate',
              'transaction_paired': false,
              'duplicate_review_token': 'review-token',
              'possible_duplicates': [
                {
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
                },
              ],
            };
          },
        ),
      );
      await _tap(tester, find.text(BankAccountStrings.emailConfirm));
      await _tap(tester, _candidate);
      await _tap(tester, _attestation);
      await _tap(tester, _submit);
      expect(calls, [false]);
      expect(find.text(BankAccountStrings.emailOutcomeConfirmed), findsNothing);
      expect(
        find.text(BankAccountStrings.emailOutcomePossibleDuplicate),
        findsOneWidget,
      );
      expect(find.textContaining('PAID91'), findsOneWidget);
      expect(_canSubmit(tester), isFalse);
      await tester.ensureVisible(_separate);
      await _tap(tester, _separate);
      expect(_canSubmit(tester), isTrue);
      await _tap(tester, _submit);
      expect(calls, [false, true]);
      expect(
        find.text(BankAccountStrings.emailOutcomeConfirmed),
        findsOneWidget,
      );
      expect(find.text(BankAccountStrings.emailQueueEmpty), findsOneWidget);
    },
  );

  testWidgets(
    'degraded email connection preserves status beside confirmation notice',
    (tester) async {
      await _connection(tester, 'degraded');
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
