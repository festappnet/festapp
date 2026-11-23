import 'package:festapp_core/payments.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/payments/payment_editor_registry.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/eshop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/payments/payment_method_cards.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

const _connection = '12345678-1234-4234-8234-123456789abc';
late WidgetEnvironmentFixture _environment;

Map<String, dynamic> _recipient({bool paused = false}) => {
  'connectionId': _connection,
  'name': 'Test organizer',
  'state': paused ? 'restricted' : 'connected',
  'modelVerified': true,
  'paused': paused,
  'chargesEnabled': !paused,
  'cardPaymentsActive': !paused,
};

FormEditBundle _bundle(
  String link,
  int unit,
  Map<String, dynamic>? payments, {
  List<BankAccountModel> accounts = const [],
  bool stripeEnabled = true,
  bool paid = true,
}) => FormEditBundle(
  form:
      FormEditorDraft(
          link: link,
          title: 'Payment test',
          occasionId: unit * 10,
          data: {
            'payments': payments == null
                ? {'bankEnabled': true}
                : {...payments},
          },
          relatedFields: [
            if (paid)
              FormFieldDraft(
                productType: ProductTypeModel(
                  products: [ProductModel(currencyCode: 'CZK', price: 100)],
                ),
              ),
          ],
          availableBankAccounts: accounts,
        )
        ..paymentMethodPolicy = {
          'preferredMethod': 'bank',
          'unitId': unit,
          'methods': {
            'bank': {'policyEnabled': true},
            'cash': {'policyEnabled': true},
            'stripe': {'policyEnabled': stripeEnabled},
            'orchard': {'policyEnabled': true},
          },
        },
  productTypes: [],
  products: [],
  availableBankAccounts: accounts,
);

EditorActionBar _actions(WidgetTester tester) =>
    tester.widget<EditorActionBar>(find.byType(EditorActionBar));
FormPaymentMethod? _selection(WidgetTester tester) =>
    tester.widget<PaymentMethodCards>(find.byType(PaymentMethodCards)).value;

Future<void> _openSection(WidgetTester tester, String title) async {
  final header = find.text(title);
  await tester.ensureVisible(header);
  await tester.tap(header);
  await tester.pumpAndSettle();
}

Future<void> _openMethods(WidgetTester tester) =>
    _openSection(tester, FormStrings.changePaymentMethod);

Future<void> _choose(WidgetTester tester, FormPaymentMethod method) async {
  final card = find.byKey(ValueKey('payment-method-${method.name}'));
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
}

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(
    () => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    ),
  );
  setUp(() {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      unit: UnitModel(
        id: 9,
        paymentMethodPolicy: const {
          'methods': {
            'stripe': {'policyEnabled': true},
          },
        },
      ),
      occasionUser: OccasionUserModel(isEditor: true),
      capabilities: const {'occasions.write': true, 'forms.write': true},
      occasion: OccasionModel(
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        features: [FormFeature(code: 'form')],
      ),
    );
  });
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);

  for (final currencies in [
    <String>['CZK'],
    <String>['EUR'],
    <String>[],
  ]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'explicit scoped bank selection is clean; account currency eligibility is visible: $currencies',
      (tester) async {
        var saves = 0;
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: FormSettingsContent(
              showCardPayments: false,
              bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
              formLink: 'default-bank-test',
              loadBundle: (link) async => _bundle(
                link,
                5,
                null,
                accounts: [
                  BankAccountModel(
                    id: 1,
                    title: 'Účet pořadatele',
                    supportedCurrencies: currencies,
                  ),
                ],
              ),
              saveForm: (_) async {
                saves++;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PaymentMethodCards), findsNothing);
        expect(_actions(tester).hasChanges, isFalse);
        expect(saves, 0);
        expect(
          find.text(BankAccountStrings.missingAccountForCurrencies('CZK')),
          currencies.contains('CZK') ? findsNothing : findsOneWidget,
        );
        if (!currencies.contains('CZK')) {
          await _openSection(tester, FormStrings.transferDetails);
          expect(
            find.text(BankAccountStrings.askManagerForPaymentAccount),
            findsOneWidget,
          );
        }
        await _openMethods(tester);
        expect(_selection(tester), FormPaymentMethod.bank);
        await _choose(tester, FormPaymentMethod.cash);
        expect(_selection(tester), FormPaymentMethod.cash);
        expect(_actions(tester).hasChanges, isTrue);
        expect(saves, 0);
      },
    );
  }

  testWidgetsWithEnvironment(
    () => _environment,
    'saved cash-only remains selected on open and after discarding a bank choice',
    (tester) async {
      var saves = 0;
      var reads = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'saved-cash-test',
            loadBundle: (link) async => _bundle(
              link,
              5,
              {
                'bankEnabled': false,
                'cashEnabled': true,
                'cashInstructions': 'Zaplaťte při příchodu u vstupu.',
              },
              accounts: [
                BankAccountModel(
                  id: 1,
                  title: 'Účet pořadatele',
                  supportedCurrencies: ['CZK'],
                ),
              ],
            ),
            loadPaymentRecipient: (_, __) async {
              reads++;
              return _recipient();
            },
            saveForm: (_) async {
              saves++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodCards), findsNothing);
      expect(_actions(tester).hasChanges, isFalse);
      expect(find.text('Zaplaťte při příchodu u vstupu.'), findsOneWidget);
      expect(reads, 0);
      await _openMethods(tester);
      expect(_selection(tester), FormPaymentMethod.cash);
      expect(reads, 0);
      await _choose(tester, FormPaymentMethod.bank);
      expect(reads, 1);
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isTrue);
      final discard = find.descendant(
        of: find.byType(EditorActionBar),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(discard);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Common.discardChanges'.tr()),
      );
      await tester.pumpAndSettle();
      expect(_selection(tester), FormPaymentMethod.cash);
      expect(_actions(tester).hasChanges, isFalse);
      expect(find.text('Zaplaťte při příchodu u vstupu.'), findsWidgets);
      expect(saves, 0);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'another connector saves its recipient without erasing other provider bindings',
    (tester) async {
      const other = PaymentConnector(
        id: 'other',
        payPath: '/payments/other/pay',
        returnPath: '/payments/other/return',
        checkoutHost: 'pay.example',
      );
      final adapter = PaymentEditorConnector(
        connector: other,
        visible: () => true,
        canManage: () => false,
        supportedCurrencies: const {'CZK'},
        titleKey: 'stripe',
        setupKey: 'setupStripe',
        settingsPath: (unit) => '/unit/$unit/edit/other',
      );
      Map<String, dynamic>? saved;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            showCardPayments: true,
            paymentProviders: [adapter],
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'other-provider',
            loadBundle: (link) async => _bundle(link, 5, {
              'bankEnabled': true,
              'stripeConnectionId': 'kept-other-binding',
              'providerConnections': {'other': _connection},
            }),
            loadPaymentRecipient: (_, __) async => _recipient(),
            saveForm: (draft) async => saved = Map<String, dynamic>.from(
              draft.toEditedJson()['settings']['payments'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openMethods(tester);
      expect(_selection(tester), FormPaymentMethod.both);
      await _choose(tester, FormPaymentMethod.online);
      await _actions(tester).onSave();
      await tester.pumpAndSettle();
      expect(saved!['bankEnabled'], false);
      expect(saved!['providerConnections'], {
        'other': _connection,
        'stripe': 'kept-other-binding',
      });
      expect(saved!.containsKey('stripeConnectionId'), isFalse);
      await _choose(tester, FormPaymentMethod.bank);
      await _actions(tester).onSave();
      await tester.pumpAndSettle();
      expect(saved!['providerConnections'], {'stripe': 'kept-other-binding'});
      expect(saved!.containsKey('stripeConnectionId'), isFalse);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'form policy hides Stripe even when the current unit enables it',
    (tester) async {
      var reads = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'hidden-payment-test',
            loadBundle: (link) async => _bundle(link, 5, {
              'bankEnabled': true,
              'stripeConnectionId': _connection,
            }, stripeEnabled: false),
            loadPaymentRecipient: (unit, occasion) async {
              reads++;
              return _recipient();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentMethodStrings.reason('payments_disabled')),
        findsOneWidget,
      );
      expect(
        find.text(PaymentMethodStrings.recipient('Test organizer')),
        findsOneWidget,
      );
      await _openMethods(tester);
      expect(find.byType(PaymentMethodCards), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-method-cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-method-bank')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-method-online')), findsNothing);
      expect(find.byKey(const ValueKey('payment-method-both')), findsNothing);
      expect(
        tester
            .widget<PaymentMethodCards>(find.byType(PaymentMethodCards))
            .value,
        FormPaymentMethod.bank,
      );
      expect(reads, 1);
      expect(_actions(tester).hasChanges, isFalse);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'verifies and retries the recipient in the scope returned by the form editor',
    (tester) async {
      final requests = <(int, int)>[];
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'stripe-verification',
            loadBundle: (link) async => _bundle(link, 5, null),
            loadPaymentRecipient: (unit, occasion) async {
              requests.add((unit, occasion));
              if (requests.length == 1) throw StateError('read failed');
              return _recipient();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await _openMethods(tester);
      expect(requests, [(5, 50)]);
      expect(
        find.text(PaymentMethodStrings.reason('unavailable')),
        findsOneWidget,
      );
      final retry = find.widgetWithText(
        TextButton,
        PaymentMethodStrings.text('checkAccount'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(requests, [(5, 50), (5, 50)]);
      expect(find.textContaining('Test organizer'), findsOneWidget);
      expect(retry, findsNothing);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'server-materialized defaults remain clean until a choice; all modes save and discard',
    (tester) async {
      Map<String, dynamic>? savedPayments;
      var checks = 0;
      var saves = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            showCardPayments: true,
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'payment-test',
            loadBundle: (link) async => _bundle(link, 5, savedPayments),
            loadPaymentRecipient: (unit, occasion) async {
              expect([unit, occasion], [5, 50]);
              checks++;
              return _recipient(paused: true);
            },
            saveForm: (draft) async {
              saves++;
              savedPayments = Map<String, dynamic>.from(
                draft.toEditedJson()['settings']['payments'],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodCards), findsNothing);
      expect(find.text(PaymentMethodStrings.reason('paused')), findsNothing);
      expect(_actions(tester).hasChanges, isFalse);
      expect(checks, 0);
      await _openMethods(tester);
      expect(checks, 1);
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isFalse);
      expect(find.text(PaymentMethodStrings.reason('paused')), findsOneWidget);

      for (final mode in [
        FormPaymentMethod.online,
        FormPaymentMethod.both,
        FormPaymentMethod.bank,
      ]) {
        await _choose(tester, mode);
        expect(_selection(tester), mode);
        expect(_actions(tester).hasChanges, isTrue);
        await _actions(tester).onSave();
        await tester.pumpAndSettle();
        expect(savedPayments!['bankEnabled'], mode != FormPaymentMethod.online);
        expect(
          (savedPayments!['providerConnections'] as Map)['stripe'],
          mode == FormPaymentMethod.bank ? null : _connection,
        );
        expect(_actions(tester).hasChanges, isFalse);
      }
      expect(saves, 3);
      await _choose(tester, FormPaymentMethod.both);
      final discard = find.descendant(
        of: find.byType(EditorActionBar),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(discard);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Common.discardChanges'.tr()),
      );
      await tester.pumpAndSettle();
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isFalse);
      expect(saves, 3);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'late recipient response from replaced form cannot change the new form',
    (tester) async {
      final pending = Completer<Map<String, dynamic>?>();
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            showCardPayments: true,
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'old-form',
            loadBundle: (link) async => _bundle(link, 5, {
              'bankEnabled': false,
              'stripeConnectionId': _connection,
            }),
            loadPaymentRecipient: (unit, occasion) => pending.future,
          ),
        ),
      );
      // Deliberately leave the old recipient request unresolved.
      await tester.pump();
      await tester.pump();
      expect(find.text(PaymentMethodStrings.text('stripe')), findsOneWidget);
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            showCardPayments: true,
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'new-form',
            loadBundle: (link) async => _bundle(link, 9, null),
            loadPaymentRecipient: (_, __) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(_recipient());
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodCards), findsNothing);
      await _openMethods(tester);
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isFalse);
      expect(find.textContaining('Test organizer'), findsNothing);
      expect(tester.takeException(), isNull);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
    },
  );
  for (final width in [360.0, 1200.0]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'settings keep saved link, availability and payment summary visible at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final inheritedWithoutDeadline = width > 1000;
        if (inheritedWithoutDeadline) {
          final feature = RightsService.currentOccasion()!.features
              .whereType<FormFeature>()
              .single;
          feature.paymentDeadlineMode = 'none';
        }
        final link = List.filled(10, 'koncert').join('-');
        var opens = 0;
        final bundle = _bundle(link, 5, null);
        bundle.form.definition = bundle.form.definition.copyWith(isOpen: false);
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: FormSettingsContent(
              bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
              formLink: link,
              loadBundle: (_) async => bundle,
              onOpenEditor: () => opens++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(FormStrings.formClosedMessage), findsOneWidget);
        expect(find.text(FormStrings.openPublicLink), findsOneWidget);
        expect(
          find.text(
            inheritedWithoutDeadline
                ? PaymentMethodStrings.text('deadlineNone')
                : FormStrings.inheritedPaymentDeadline(7),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(FormStrings.paymentQrSummary(true)),
          findsOneWidget,
        );
        expect(find.byType(PaymentMethodCards), findsNothing);
        expect(find.text(FormStrings.embedAction), findsNothing);
        expect(find.text(FormStrings.customerEmails), findsOneWidget);
        final availability = find.text(FormStrings.openFormTab);
        await tester.ensureVisible(availability);
        await tester.tap(availability);
        expect(opens, 1);
        final hiddenLinkInput = find.descendant(
          of: find.widgetWithText(
            TextFormField,
            FormStrings.labelFormLink,
            skipOffstage: false,
          ),
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        );
        expect(
          tester
              .widget<EditableText>(hiddenLinkInput)
              .focusNode
              .canRequestFocus,
          isFalse,
        );
        final linkHeader = find.text(FormStrings.publicLinkSettings);
        await tester.ensureVisible(linkHeader);
        Focus.of(tester.element(linkHeader)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(_actions(tester).hasChanges, isFalse);
        final field = find.widgetWithText(
          TextFormField,
          FormStrings.labelFormLink,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, 'nova-adresa');
        await tester.pumpAndSettle();
        final publicLink = tester.widget<PublicLink>(find.byType(PublicLink));
        expect(publicLink.savedLink, link);
        expect(publicLink.link, 'nova-adresa');
        expect(
          tester.widget<CopyButton>(find.byType(CopyButton)).value,
          publicLinkUrl(link),
        );
        expect(find.text(publicLinkUrl('nova-adresa')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgetsWithEnvironment(
    () => _environment,
    'saving opens and focuses an invalid field inside a collapsed section',
    (tester) async {
      var saves = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'form-validation',
            loadBundle: (link) async => _bundle(link, 5, null),
            saveForm: (_) async {
              saves++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openSection(tester, FormStrings.customerEmails);
      final interval = find.widgetWithText(
        TextFormField,
        FormStrings.labelReminderInterval,
      );
      await tester.ensureVisible(interval);
      await tester.enterText(interval, 'invalid');
      await _openSection(tester, FormStrings.customerEmails);
      expect(interval, findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Common.save'.tr()));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.text(FormStrings.nonNegativeDays), findsOneWidget);
      final input = find.descendant(
        of: interval,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
      expect(
        tester.getBottomLeft(interval).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(EditorActionBar)).dy),
      );
      await tester.enterText(interval, '2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Common.save'.tr()));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(_actions(tester).hasChanges, isFalse);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'active Stripe failure stays visible before expanding payment controls',
    (tester) async {
      var attempts = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'stripe-active',
            loadBundle: (link) async => _bundle(link, 5, {
              'bankEnabled': false,
              'stripeConnectionId': _connection,
            }),
            loadPaymentRecipient: (_, _) async {
              if (++attempts == 1) throw StateError('read failed');
              return _recipient(paused: true);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodCards), findsNothing);
      expect(find.text(FormStrings.cardPaymentAtCheckout), findsOneWidget);
      expect(find.text(FormStrings.inheritedPaymentDeadline(7)), findsNothing);
      expect(
        find.text(PaymentMethodStrings.reason('unavailable')),
        findsOneWidget,
      );
      final retry = find.text(PaymentMethodStrings.text('checkAccount'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text(PaymentMethodStrings.reason('paused')), findsOneWidget);
      expect(
        find.text(PaymentMethodStrings.recipient('Test organizer')),
        findsOneWidget,
      );
      expect(_actions(tester).hasChanges, isFalse);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'free form keeps payment controls without a missing account warning',
    (tester) async {
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            showCardPayments: false,
            formLink: 'free-form',
            loadBundle: (link) async => _bundle(link, 5, null, paid: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.noPaidProducts), findsOneWidget);
      expect(
        find.text(BankAccountStrings.askManagerForPaymentAccount),
        findsNothing,
      );
      await _openMethods(tester);
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isFalse);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'read-only settings retain the public URL and hide payment authoring',
    (tester) async {
      final rights = RightsService.occasionLinkModelNotifier.value!;
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: rights.unit,
        occasion: rights.occasion,
      );
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            formLink: 'read-only',
            loadBundle: (link) async => _bundle(link, 5, null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(publicLinkUrl('read-only')), findsOneWidget);
      expect(find.byType(CopyButton), findsOneWidget);
      expect(find.text(FormStrings.changePaymentMethod), findsNothing);
      expect(_actions(tester).enabled, isFalse);
      final focus = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(focus)));
    },
  );
}
