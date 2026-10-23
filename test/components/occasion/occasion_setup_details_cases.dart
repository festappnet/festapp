import 'package:fstapp/components/bank_accounts/views/unit_bank_account_card.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_sync_status.dart';
import 'package:festapp_core/forms.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/views/form_variable_symbol_settings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_form_link.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_pricing.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_bank_account.dart';

import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('variable symbols use canonical form metadata', (tester) async {
    var metadata = <String, dynamic>{
      FormDefinition.metaType: 'sequence',
      FormDefinition.metaStartingNumber: 202600,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FormVariableSymbolSettings(
              value: metadata,
              onChanged: (value) => setState(() => metadata = value),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '202601');
    expect(metadata, {
      FormDefinition.metaType: 'sequence',
      FormDefinition.metaStartingNumber: 202601,
    });
  });

  testWidgets('promotion requires an image and only changes promotion', (
    tester,
  ) async {
    final data = <String, dynamic>{'isPromoted': false};
    Map<String, dynamic>? patch;
    Future<void> render() => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OccasionSetupPromotion(
                data: data,
                onChanged: (value) => patch = value,
              ),
            ),
          ),
        );
    await render();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    data['introImage'] = 'https://example.org/image.jpg';
    await render();
    await tester.tap(find.byType(SwitchListTile));
    expect(patch, {'isPromoted': true});
  });

  testWidgets(
    'suggestion uses server availability and manual edits are retained',
    (tester) async {
      var value = '';
      var automatic = true;
      bool? valid;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => OccasionSetupFormLink(
                draftId: 'draft',
                title: 'Ples',
                value: value,
                automatic: automatic,
                onChanged: (v, a) => setState(() {
                  value = v;
                  automatic = a;
                }),
                onValidityChanged: (v) => valid = v,
                suggest: (title, requested) async => {
                  'suggestion': 'ples-2090-2',
                  'available': requested == 'ples-2090-2',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(value, 'ples-2090-2');
      expect(automatic, true);
      expect(valid, true);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(TextButton).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'taken');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(value, 'taken');
      expect(automatic, false);
      expect(valid, false);
      expect(find.text('OccasionSetup.setupDetails.linkTaken'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('resuming and changing title updates automatic suggestion only', (
    tester,
  ) async {
    var value = 'registration-2090';
    var title = 'Old';
    var automatic = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return OccasionSetupFormLink(
                draftId: 'draft',
                title: title,
                value: value,
                automatic: automatic,
                onChanged: (v, a) => setState(() {
                  value = v;
                  automatic = a;
                }),
                suggest: (t, r) async => {
                  'suggestion': t == 'Old' ? 'old-2090' : 'new-2090',
                  'available': true,
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(value, 'old-2090');
    update(() => title = 'New');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(value, 'new-2090');
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(TextButton).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'personal-address');
    update(() => title = 'Another');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(value, 'personal-address');
    expect(automatic, false);
    await tester.pumpWidget(const SizedBox());
  });
  test(
      'draft waves round-trip through actual editor bundle without scheduling writes',
      () async {
    final data = <String, dynamic>{
      'formDraft': {
        'title': 'Form',
        'fields': [
          {
            'type': 'product_type',
            'product_type_data': {
              'id': 10,
              'type': 'spot',
              'title': 'Ticket',
              'products': [
                {
                  'id': 100,
                  'title': 'Admission',
                  'price': 100,
                  'currency_code': 'CZK',
                },
              ],
            },
          },
        ],
      },
    };
    final draft = OccasionSetupPriceWaveDraft(
      data,
      (patch) => data.addAll(patch),
    );
    final time = DateTime.now().add(const Duration(days: 20));
    final wave = await draft.create(time);
    final product = draft.bundle().products.single;
    await draft.saveTarget(wave, product, 150, null);
    expect(draft.bundle().products.single.priceChanges.single.price, 150);
    expect(
      (data['priceWaves'] as List).single['targets'].single['product'],
      100,
    );
    final moved = time.add(const Duration(days: 1));
    await draft.move(wave, moved);
    expect(draft.bundle().priceWaves.single.time, moved.toUtc());
    await draft.cancel(wave);
    expect(draft.bundle().products.single.priceChanges, isEmpty);
  });
  test('draft first target writes the entire local intention once', () async {
    final data = <String, dynamic>{};
    var saves = 0;
    final draft = OccasionSetupPriceWaveDraft(data, (patch) {
      saves++;
      data.addAll(patch);
    });
    final time = DateTime.now().add(const Duration(days: 20));
    await draft.saveTarget(
        ProductPriceWave(time: time), ProductModel(id: 100), 150, false);
    expect(saves, 1);
    final wave = (data['priceWaves'] as List).single;
    expect(wave['targets'], [
      {'product': 100, 'price': 150.0, 'is_hidden': false}
    ]);
  });
  testWidgets(
    'selected account is ready without checkbox and currency changes invalidate it',
    (tester) async {
      final data = <String, dynamic>{
        'formDraft': {
          'fields': [
            {
              'product_type_data': {
                'products': [
                  {'id': 1, 'price': 100, 'currency_code': 'CZK'},
                ],
              },
            },
          ],
        },
      };
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return OccasionSetupBankAccount(
                  draftId: 'draft',
                  unitId: 1,
                  data: data,
                  onChanged: (patch) => setState(() => data.addAll(patch)),
                  loader: () async => {
                    'canManage': true,
                    'accounts': [
                      {
                        'id': 7,
                        'title': 'Main',
                        'display': '123/0100',
                        'currencies': ['CZK'],
                        'fingerprint': 'digest',
                      },
                    ],
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UnitBankAccountCard), findsOneWidget);
      expect(find.byType(BankAccountSyncStatus), findsOneWidget);
      expect(find.byType(Radio<int>), findsOneWidget);
      expect(find.byIcon(Icons.link_off), findsNothing);
      expect(data['bankAccountId'], 7);
      expect(find.byType(Checkbox), findsNothing);
      expect(data.containsKey('bankAccountConfirmed'), isFalse);
      expect(data['bankAccountFingerprint'], 'digest');
      update(
        () => ((data['formDraft'] as Map)['fields'] as List)
            .first['product_type_data']['products']
            .first['currency_code'] = 'EUR',
      );
      await tester.pumpAndSettle();
      expect(data['bankAccountId'], isNull);
      expect(data.containsKey('bankAccountConfirmed'), isFalse);
      expect(
        find.text('OccasionSetup.setupDetails.bankMissing'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'missing account offers setup and reloads a verified selection',
    (tester) async {
      final data = <String, dynamic>{};
      var created = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => OccasionSetupBankAccount(
                draftId: 'draft',
                unitId: 1,
                data: data,
                onChanged: (patch) => setState(() => data.addAll(patch)),
                loader: () async => {
                  'canManage': true,
                  'accounts': created
                      ? [
                          {
                            'id': 9,
                            'title': 'New',
                            'display': '456/0100',
                            'currencies': ['CZK'],
                            'fingerprint': 'new',
                          },
                        ]
                      : [],
                },
                setup: (_) async {
                  created = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('OccasionSetup.setupDetails.setupBankAccount'),
      );
      await tester.pumpAndSettle();
      expect(created, true);
      expect(data['bankAccountId'], 9);
      expect(data.containsKey('bankAccountConfirmed'), isFalse);
    },
  );
}
