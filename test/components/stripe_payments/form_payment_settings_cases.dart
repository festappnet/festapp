import 'package:festapp_core/payments.dart';
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
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/payments/payment_method_cards.dart';
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

FormEditBundle _bundle(String link, int unit, Map<String, dynamic>? payments) =>
    FormEditBundle(
      form: FormEditorDraft(
        link: link,
        title: 'Payment test',
        occasionId: unit * 10,
        occasionModel: OccasionModel(
          unit: unit,
          isOpen: true,
          isHidden: false,
          isPromoted: false,
        ),
        data: {
          if (payments != null) 'payments': {...payments},
        },
        relatedFields: [
          FormFieldDraft(
            productType: ProductTypeModel(
              products: [ProductModel(currencyCode: 'CZK')],
            ),
          ),
        ],
        availableBankAccounts: [],
      ),
      productTypes: [],
      products: [],
      availableBankAccounts: [],
    );

EditorActionBar _actions(WidgetTester tester) =>
    tester.widget<EditorActionBar>(find.byType(EditorActionBar));
FormPaymentMethod? _selection(WidgetTester tester) =>
    tester.widget<PaymentMethodCards>(find.byType(PaymentMethodCards)).value;

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
      expect(_selection(tester), FormPaymentMethod.both);
      await _choose(tester, FormPaymentMethod.online);
      await _actions(tester).onSave();
      await tester.pumpAndSettle();
      expect(saved!['bankEnabled'], false);
      expect(saved!['providerConnections'], {'other': _connection, 'stripe': 'kept-other-binding'});
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
    'normal form settings expose cash without Stripe reads or configuration changes',
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
            }),
            loadPaymentRecipient: (unit, occasion) async {
              reads++;
              return _recipient();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodCards), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-method-cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-method-bank')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-method-online')), findsNothing);
      expect(find.byKey(const ValueKey('payment-method-both')), findsNothing);
      expect(tester.widget<PaymentMethodCards>(find.byType(PaymentMethodCards)).value,
          FormPaymentMethod.bank);
      expect(reads, 0);
      expect(_actions(tester).hasChanges, isFalse);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'legacy defaults remain clean until a choice; all modes save and discard',
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
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isFalse);
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
            key: const ValueKey('old-form'),
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
      expect(_selection(tester), FormPaymentMethod.online);
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormSettingsContent(
            showCardPayments: true,
            bankConnectionChanges: ValueNotifier((accountId: 0, revision: 0)),
            key: const ValueKey('new-form'),
            formLink: 'new-form',
            loadBundle: (link) async => _bundle(link, 9, null),
            loadPaymentRecipient: (_, __) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(_recipient());
      await tester.pumpAndSettle();
      expect(_selection(tester), FormPaymentMethod.bank);
      expect(_actions(tester).hasChanges, isFalse);
      expect(find.textContaining('Test organizer'), findsNothing);
      expect(tester.takeException(), isNull);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
    },
  );
}
